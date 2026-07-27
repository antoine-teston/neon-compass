#!/usr/bin/env node
// Console web locale pour piloter content-cli sans passer par le terminal.
//
//   npm run ui            puis ouvrir l'URL affichée
//   npm run ui -- --port 5000
//
// Pourquoi un serveur local et pas une page statique : ces actions lancent des
// processus et touchent au dépôt ou à Firestore. Aucune page hébergée ne peut le
// faire — il faut un processus sur la machine.
//
// Trois garde-fous, dans cet ordre d'importance :
//
// 1. Écoute sur 127.0.0.1 uniquement. Un serveur qui lance des commandes ne doit
//    pas être joignable depuis le réseau, jamais, même sur un LAN de confiance.
// 2. Aucune donnée de requête n'atteint une ligne de commande : les actions sont
//    une liste blanche d'`argv` fixes (ui/actions.mjs), et `spawn` est appelé
//    sans shell.
// 3. Les actions qui écrivent en production exigent une confirmation explicite
//    dans le corps de la requête ET des credentials présents. Un GET perdu ou un
//    rechargement de page ne peut rien publier.

import { execFileSync, spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ACTIONS, resolveAction } from './actions.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI_DIR = join(HERE, '..');
const ROOT = join(CLI_DIR, '..', '..');
const CONTENT = join(ROOT, 'content');

const portArg = process.argv.indexOf('--port');
const PORT = portArg === -1 ? 4321 : Number(process.argv[portArg + 1]);

function credentialsPresent() {
  const path = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  return Boolean(path && existsSync(path));
}

function git(args) {
  try {
    return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
}

/** Inventaire du contenu : ce qu'une interface apporte de plus qu'un bouton —
 *  voir d'un coup d'œil ce qui partirait, et ce qui attend une décision. */
function inventory() {
  const kinds = {};
  for (const kind of ['poi', 'poi-gtav', 'cheats', 'collections']) {
    const dir = join(CONTENT, kind);
    if (!existsSync(dir)) continue;
    const files = readdirSync(dir).filter((f) => f.endsWith('.json'));
    let published = 0;
    for (const f of files) {
      if (JSON.parse(readFileSync(join(dir, f), 'utf8')).status === 'published') published++;
    }
    kinds[kind] = { total: files.length, published, draft: files.length - published };
  }

  // Les collections méritent leur propre coup d'œil : un défi sans total attendu
  // s'affiche en décompte brut côté app, ce qui est voulu mais mérite d'être vu.
  const collectionsDir = join(CONTENT, 'collections');
  const collections = existsSync(collectionsDir)
    ? readdirSync(collectionsDir)
        .filter((f) => f.endsWith('.json'))
        .map((f) => JSON.parse(readFileSync(join(collectionsDir, f), 'utf8')))
        .sort((a, b) => a.id.localeCompare(b.id))
    : [];

  return { kinds, collections };
}

function state() {
  // `check-seeds` est rapide et sans réseau : on peut l'exécuter à chaque
  // rafraîchissement plutôt que de dupliquer sa logique ici.
  let seedsUpToDate = null;
  try {
    execFileSync(process.execPath, ['cli.js', 'check-seeds'], { cwd: CLI_DIR, stdio: 'pipe' });
    seedsUpToDate = true;
  } catch {
    seedsUpToDate = false;
  }

  const dirty = git(['status', '--porcelain']);
  return {
    credentials: credentialsPresent(),
    seedsUpToDate,
    git: {
      branch: git(['rev-parse', '--abbrev-ref', 'HEAD']),
      commit: git(['rev-parse', '--short', 'HEAD']),
      dirtyCount: dirty ? dirty.split('\n').length : 0,
    },
    ...inventory(),
  };
}

function send(res, status, body, type = 'application/json') {
  const payload = type === 'application/json' ? JSON.stringify(body) : body;
  res.writeHead(status, {
    'content-type': `${type}; charset=utf-8`,
    // Rien de tout ça ne doit être mis en cache : l'état change à chaque action.
    'cache-control': 'no-store',
  });
  res.end(payload);
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (!chunks.length) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return {};
  }
}

/** Exécute l'action et diffuse sa sortie au fil de l'eau. Le flux porte aussi le
 *  code retour en dernière ligne : le client sait si ça a réussi sans requête
 *  supplémentaire. */
function stream(res, argv) {
  res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });

  // Toujours `node <argv>`, jamais `shell: true` : les éléments d'argv sont
  // passés tels quels au processus, sans interprétation. C'est ce qui rend
  // l'identifiant de modération inoffensif même s'il contenait des
  // métacaractères.
  const child = spawn(process.execPath, argv, { cwd: CLI_DIR });

  child.stdout.on('data', (d) => res.write(d));
  child.stderr.on('data', (d) => res.write(d));
  child.on('error', (err) => res.end(`\n__EXIT__:1\n${err.message}\n`));
  child.on('close', (code) => res.end(`\n__EXIT__:${code ?? 1}\n`));
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (req.method === 'GET' && url.pathname === '/') {
    return send(res, 200, readFileSync(join(HERE, 'index.html'), 'utf8'), 'text/html');
  }

  if (req.method === 'GET' && url.pathname === '/api/state') {
    return send(res, 200, { ...state(), actions: publicActions() });
  }

  if (req.method === 'POST' && url.pathname === '/api/run') {
    const body = await readBody(req);
    let resolved;
    try {
      resolved = resolveAction(body.action, { id: body.id });
    } catch (err) {
      return send(res, 400, { error: err.message });
    }
    const { action, argv } = resolved;

    // L'intention avant la capacité : une action de production sans
    // confirmation est refusée même sans credentials. L'ordre inverse rendait ce
    // garde-fou impossible à vérifier sur une machine sans clé.
    //
    // La confirmation vit dans le corps de la requête, pas dans l'URL : un lien
    // partagé ou un rechargement de page ne peut donc rien déclencher.
    if (action.destructive && body.confirm !== true) {
      return send(res, 428, { error: 'confirmation requise pour une action de production' });
    }
    if ((action.destructive || action.needsCredentials) && !credentialsPresent()) {
      return send(res, 412, {
        error: 'FIREBASE_SERVICE_ACCOUNT_PATH absent ou introuvable — voir docs/ops/2026-07-27-content-publishing.md',
      });
    }

    return stream(res, argv);
  }

  send(res, 404, { error: 'not found' });
});

/** Ce que le client a besoin de savoir : jamais l'argv. */
function publicActions() {
  return Object.fromEntries(
    Object.entries(ACTIONS).map(([name, a]) => [
      name,
      {
        label: a.label,
        group: a.group,
        hint: a.hint ?? null,
        destructive: Boolean(a.destructive),
        needsCredentials: Boolean(a.destructive || a.needsCredentials),
        needsID: Boolean(a.needsID),
        writesRepo: Boolean(a.writesRepo),
        slow: Boolean(a.slow),
      },
    ]),
  );
}

// 127.0.0.1 explicitement, pas 0.0.0.0 : ce serveur lance des processus, il n'a
// rien à faire sur le réseau.
server.listen(PORT, '127.0.0.1', () => {
  console.log(`Console contenu  ->  http://127.0.0.1:${PORT}`);
  console.log(credentialsPresent()
    ? '  credentials Firebase détectés — les actions de production sont disponibles'
    : '  FIREBASE_SERVICE_ACCOUNT_PATH absent — seuls les contrôles et écritures locales sont disponibles');
});
