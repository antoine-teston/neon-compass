#!/usr/bin/env node
// Console de pilotage locale — contenu, GitHub, et le carnet de hotfix.
//
//   npm run ui            puis ouvrir l'URL affichée
//   npm run ui -- --port 5000
//
// Pourquoi un serveur local et pas une page statique : ces actions lancent des
// processus et touchent au dépôt ou à Supabase. Aucune page hébergée ne peut le
// faire — il faut un processus sur la machine.
//
// ─────────────────────────────────────────────────────────────────────────────
// DEUX PORTES, DEUX INVARIANTS. C'est la structure du fichier, et ce n'est pas
// une préférence de style : chacune se résume en une phrase qu'un test vérifie.
//
//   PORTE « GESTE » — POST /api/run
//   Rien du corps de la requête n'atteint une ligne de commande, hors paramètres
//   DÉCLARÉS et validés par motif (ui/actions.mjs). Un paramètre non déclaré est
//   un refus. `spawn` est appelé sans shell, le binaire vient de la déclaration
//   de l'action, jamais de la requête.
//
//   PORTE « ÉDITION » — GET/PUT /api/draft/:kind/:id
//   Elle n'exécute AUCUN processus. Pas de `spawn`, pas d'`execFile`, ni ici ni
//   dans ui/drafts.mjs. Il n'y a donc rien à injecter — pas « rien
//   d'exploitable », rien du tout, par construction.
//
// ─────────────────────────────────────────────────────────────────────────────
// Trois garde-fous, dans cet ordre d'importance :
//
// 1. Écoute sur 127.0.0.1 uniquement. Un serveur qui lance des commandes ne doit
//    pas être joignable depuis le réseau, jamais, même sur un LAN de confiance.
// 2. Les deux invariants ci-dessus.
// 3. Les actions qui écrivent en production exigent une confirmation explicite
//    dans le corps de la requête ET des credentials présents. Un GET perdu ou un
//    rechargement de page ne peut rien publier.

import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ACTIONS, resolveAction } from './actions.mjs';
import { CARNET, FICHES } from './hotfix.mjs';
import {
  EDITABLE_KINDS,
  RefusedError,
  readDraft,
  statistiques,
  triageAll,
  writeDraft,
} from './drafts.mjs';
import {
  CREDENTIALS_MANQUANTS,
  cartesInstantanees,
  cartesReseau,
  credentialsPresent,
} from './state.mjs';
import { instantane } from '../../monitor/metrics.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI_DIR = join(HERE, '..');

const portArg = process.argv.indexOf('--port');
const PORT = portArg === -1 ? 4321 : Number(process.argv[portArg + 1]);

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
function stream(res, argv, bin) {
  res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });

  // Jamais `shell: true` : les éléments d'argv sont passés tels quels au
  // processus, sans interprétation. C'est ce qui rend l'identifiant de
  // modération inoffensif même s'il contenait des métacaractères.
  //
  // `bin` vient de la DÉCLARATION de l'action, jamais de la requête — c'est ce
  // qui empêche « et si on choisissait le binaire ? » d'exister comme question.
  const child = spawn(bin ?? process.execPath, argv, { cwd: CLI_DIR });

  child.stdout.on('data', (d) => res.write(d));
  child.stderr.on('data', (d) => res.write(d));
  child.on('error', (err) => res.end(`\n__EXIT__:1\n${err.message}\n`));
  child.on('close', (code) => res.end(`\n__EXIT__:${code ?? 1}\n`));
}

/** Ce que le client a besoin de savoir : jamais l'argv, jamais le binaire. */
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
        // Le motif n'est PAS envoyé : le client n'a pas à le connaître, et le
        // publier inviterait à valider côté page plutôt que côté serveur.
        params: Object.fromEntries(
          Object.entries(a.params ?? {}).map(([k, spec]) => [
            k,
            { required: Boolean(spec.required), default: spec.default ?? null },
          ]),
        ),
      },
    ]),
  );
}

/** Le carnet tel que la page l'affiche : l'ordre des fiches, plus le libellé de
 *  l'action qu'elles décrivent. */
function publicCarnet() {
  return CARNET.map((fiche) => ({ ...fiche, label: ACTIONS[fiche.action]?.label ?? fiche.action }));
}

const ROUTE_DRAFT = /^\/api\/draft\/([^/]+)\/([^/]+)$/;

/** Les fichiers que la page a le droit de demander.
 *
 *  Une LISTE BLANCHE, comme les actions, et pour la même raison : aucun chemin
 *  venu de la requête n'atteint le disque. `join(HERE, url.pathname)` aurait
 *  suffi et aurait été faux — c'est la porte par laquelle on lit
 *  `../../.env` un jour. */
const MONITOR = join(CLI_DIR, '..', 'monitor');

const FICHIERS = {
  '/': [join(HERE, 'index.html'), 'text/html'],
  '/console.js': [join(HERE, 'console.js'), 'text/javascript'],
  '/layout.mjs': [join(HERE, 'layout.mjs'), 'text/javascript'],
  // Partagés avec le moniteur du Raspberry Pi. Servis depuis `tools/monitor/`
  // plutôt que recopiés : deux copies auraient divergé, et les couleurs de ces
  // fichiers sont calculées — une valeur recopiée à la main perd sa preuve.
  '/graphes.css': [join(MONITOR, 'graphes.css'), 'text/css'],
  '/graphes.mjs': [join(MONITOR, 'graphes.mjs'), 'text/javascript'],
};

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (req.method === 'GET' && FICHIERS[url.pathname]) {
    const [chemin, type] = FICHIERS[url.pathname];
    return send(res, 200, readFileSync(chemin, 'utf8'), type);
  }

  // Les cartes INSTANTANÉES : disque seul, aucune attente.
  if (req.method === 'GET' && url.pathname === '/api/state') {
    return send(res, 200, {
      ...cartesInstantanees(),
      credentialsMessage: CREDENTIALS_MANQUANTS,
      actions: publicActions(),
      carnet: publicCarnet(),
      kinds: EDITABLE_KINDS,
    });
  }

  // Les cartes RÉSEAU, à part : la page les demande après avoir déjà affiché le
  // reste. Un jeton absent ou un réseau lent ne doit pas retarder les brouillons.
  if (req.method === 'GET' && url.pathname === '/api/state/network') {
    return send(res, 200, await cartesReseau());
  }

  // Les métriques de production, par le MÊME chemin que le moniteur du
  // Raspberry Pi : la fonction `metrics`, un jeton, et rien que des nombres.
  //
  // Passer par là plutôt que d'interroger Postgres avec la clé `service_role`
  // qu'on a pourtant sous la main est délibéré — c'est ce qui fait que le
  // chemin du Pi est exercé tous les jours depuis le Mac, au lieu d'être
  // découvert cassé sur une étagère à l'autre bout de la maison.
  if (req.method === 'GET' && url.pathname === '/api/state/supabase') {
    return send(res, 200, await instantane(process.env));
  }

  if (req.method === 'GET' && url.pathname === '/api/drafts') {
    const triage = triageAll();
    // Les statistiques voyagent avec le triage : elles en sont dérivées, et les
    // recalculer dans la page rendrait les graphes invérifiables autrement qu'à
    // l'œil. Le jour est passé en paramètre plutôt que lu par le calcul, pour que
    // celui-ci se teste sans dépendre de la date d'exécution.
    const stats = statistiques(triage, new Date().toISOString().slice(0, 10));
    return send(res, 200, { ...triage, stats });
  }

  // ---- Porte « édition » : aucun processus lancé ici -----------------------
  const draftRoute = url.pathname.match(ROUTE_DRAFT);
  if (draftRoute && (req.method === 'GET' || req.method === 'PUT')) {
    const [, kind, id] = draftRoute.map(decodeURIComponent);
    try {
      if (req.method === 'GET') return send(res, 200, readDraft(kind, id));
      const body = await readBody(req);
      return send(res, 200, writeDraft(kind, id, body));
    } catch (err) {
      // 400 par défaut : une erreur qu'on n'a pas su classer n'est jamais un
      // succès, et jamais une erreur serveur qu'on pourrait ignorer.
      return send(res, err instanceof RefusedError ? err.status : 400, { error: err.message });
    }
  }

  // ---- Porte « geste » : liste blanche d'argv ------------------------------
  if (req.method === 'POST' && url.pathname === '/api/run') {
    const body = await readBody(req);
    const { action: name, confirm, ...params } = body;
    let resolved;
    try {
      resolved = resolveAction(name, params);
    } catch (err) {
      return send(res, 400, { error: err.message });
    }
    const { action, argv, bin } = resolved;

    // L'intention avant la capacité : une action de production sans
    // confirmation est refusée même sans credentials. L'ordre inverse rendait ce
    // garde-fou impossible à vérifier sur une machine sans clé.
    //
    // La confirmation vit dans le corps de la requête, pas dans l'URL : un lien
    // partagé ou un rechargement de page ne peut donc rien déclencher.
    if (action.destructive && confirm !== true) {
      return send(res, 428, { error: 'confirmation requise pour une action de production' });
    }
    // Les actions qui passent par `gh` ne demandent PAS les credentials
    // Supabase : leur pouvoir est celui du jeton GitHub, et exiger une clé sans
    // rapport ferait échouer un correctif pour une mauvaise raison.
    if ((action.destructive || action.needsCredentials) && !bin && !credentialsPresent()) {
      return send(res, 412, { error: CREDENTIALS_MANQUANTS });
    }

    return stream(res, argv, bin);
  }

  send(res, 404, { error: 'not found' });
});

// 127.0.0.1 explicitement, pas 0.0.0.0 : ce serveur lance des processus, il n'a
// rien à faire sur le réseau.
server.listen(PORT, '127.0.0.1', () => {
  const { brouillons } = cartesInstantanees();
  console.log(`Console de pilotage  ->  http://127.0.0.1:${PORT}`);
  if (brouillons.totaux) {
    console.log(
      `  ${brouillons.totaux.attend} brouillon(s) attendent une décision, `
      + `${brouillons.totaux.retenu} retenu(s) par une règle`,
    );
  }
  console.log(credentialsPresent()
    ? '  credentials Supabase détectés — les actions de production sont disponibles'
    : `  ${CREDENTIALS_MANQUANTS}`);
});

export { publicActions, publicCarnet, FICHES };
