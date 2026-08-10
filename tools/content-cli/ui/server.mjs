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
  deleteDraft,
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
import { apercu } from '../deliver.mjs';

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
const ROUTE_PULL = /^\/api\/pulls\/(\d{1,6})$/;

/**
 * Les préconditions, par nom. Une action peut en DÉCLARER une (`actions.mjs`) ;
 * elle est évaluée ICI, au moment du geste, avant que le moindre processus ne
 * soit lancé.
 *
 * Pourquoi côté serveur et pas dans la page : la console n'a aucune
 * authentification. Un bouton grisé est un confort ; il n'a jamais arrêté une
 * requête forgée. C'est aussi ce qui règle la course « CI verte au chargement,
 * commit arrivé depuis » — on regarde l'état au moment de fusionner, pas au
 * moment d'afficher.
 *
 * Une action qui déclare une précondition sans implémentation ici est une
 * erreur attrapée par `actions.test.mjs`, pas un silence qui laisserait passer.
 */
const PRECONDITIONS = {
  'pr-fusionnable': async ({ numero }) => {
    // On LIT le refus, on ne le recalcule pas. `pullRequestOuverte` rappelle
    // `gh` à chaque geste : la valeur qu'elle porte est datée de maintenant,
    // ce qui est tout ce que ce contrôle demandait.
    //
    // Le rejuger ici, c'était le rejuger sur la vue publique — qui ne porte ni
    // `files` ni `statusCheckRollup`. Toute PR partait alors en « ne change
    // aucun fichier », et aucune n'était fusionnable depuis la console.
    const { pullRequestOuverte, refusDeFusion } = await import('./pulls.mjs');
    const pr = await pullRequestOuverte(numero);
    return pr ? pr.refus : refusDeFusion(null); // le 404 garde une seule source
  },
};

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
  '/indicateurs.mjs': [join(HERE, 'indicateurs.mjs'), 'text/javascript'],
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

  // Ce que la livraison ferait, sans rien écrire. En LECTURE pure : `apercu()`
  // n'exécute que des `git status` / `git log`.
  //
  // Une route à part plutôt qu'un `deliver.mjs --dry-run` lancé par la porte
  // « geste » : la répétition n'est utile qu'à qui pense à la lancer, et la
  // question « qu'est-ce qui partirait ? » doit se lire sans appuyer sur quoi
  // que ce soit. C'est aussi ce qui révèle ce que la livraison n'emporte PAS.
  if (req.method === 'GET' && url.pathname === '/api/livraison') {
    try {
      return send(res, 200, apercu());
    } catch (err) {
      return send(res, 200, { indisponible: `git muet — ${err.message}` });
    }
  }

  // La référence des fonctions, la MÊME que `cli.js doc` rend au terminal.
  //
  // Une route et non un fichier de la liste blanche : le markdown vit dans
  // `docs/ops/`, pas dans `ui/`. L'ajouter à `FICHIERS` aurait fait servir un
  // fichier hors de l'interface par le chemin prévu pour ses propres actifs —
  // c'est-à-dire ouvrir d'un cran une porte dont l'étroitesse est le garde-fou.
  //
  // Aucun processus lancé, aucun paramètre lu : elle rend un fichier du dépôt,
  // toujours le même.
  if (req.method === 'GET' && url.pathname === '/api/doc') {
    try {
      const { enHTML, lire, sections } = await import('../doc.mjs');
      const markdown = lire();
      return send(res, 200, {
        html: enHTML(markdown),
        sections: sections(markdown).map(({ rang, titre }) => ({ rang, titre })),
      });
    } catch (err) {
      // Une référence introuvable ne doit pas faire tomber la console : elle
      // affiche pourquoi, comme toutes les cartes de ce tableau de bord.
      return send(res, 200, { indisponible: err.message });
    }
  }

  // La relecture d'une PR : lecture éditoriale, diff brut, et l'effet du merge.
  //
  // Le `git fetch` qu'elle déclenche ne touche ni `HEAD` ni l'arbre de travail —
  // il pose une référence sous `refs/console/pr/`, à nous, effaçable.
  const routePull = url.pathname.match(ROUTE_PULL);
  if (req.method === 'GET' && routePull) {
    try {
      const { relectureDe } = await import('./pulls.mjs');
      return send(res, 200, await relectureDe(Number(routePull[1])));
    } catch (err) {
      // 200 avec `indisponible`, comme les cartes : la boîte doit pouvoir dire
      // pourquoi elle est vide plutôt que de rester vide.
      return send(res, 200, { indisponible: err.message });
    }
  }

  // Le verdict de publication du merge qu'on vient de faire. `depuis` (ISO)
  // écarte les runs d'avant — sans lui on lirait celui du merge précédent.
  if (req.method === 'GET' && url.pathname === '/api/pulls/publication') {
    try {
      const { derniersRuns, journalDeRun } = await import('./runs.mjs');
      const { verdictDePublication } = await import('./pulls.mjs');
      const depuis = url.searchParams.get('depuis');
      const [run] = await derniersRuns('content.yml', { limite: 5, depuis });
      if (!run) return send(res, 200, { attente: 'aucun run déclenché pour l’instant' });
      if (run.status !== 'completed') return send(res, 200, { run, attente: `run ${run.status}` });
      return send(res, 200, { run, ...verdictDePublication(await journalDeRun(run.databaseId)) });
    } catch (err) {
      return send(res, 200, { indisponible: `publication illisible — ${err.message}` });
    }
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
  if (draftRoute && ['GET', 'PUT', 'DELETE'].includes(req.method)) {
    const [, kind, id] = draftRoute.map(decodeURIComponent);
    try {
      if (req.method === 'GET') return send(res, 200, readDraft(kind, id));
      const body = await readBody(req);
      // `DELETE` reste dans cette porte : il ne lance aucun processus non plus.
      // Le corps porte l'empreinte — écarter un fichier que quelqu'un vient de
      // modifier, c'est jeter son travail sans le lui dire.
      if (req.method === 'DELETE') return send(res, 200, deleteDraft(kind, id, body));
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

    // La précondition en DERNIER : elle interroge le réseau, et il n'y a aucune
    // raison de payer cet appel pour une requête qu'on aurait refusée de toute
    // façon.
    if (action.precondition) {
      const controle = PRECONDITIONS[action.precondition];
      if (!controle) {
        return send(res, 500, { error: `précondition « ${action.precondition} » sans implémentation` });
      }
      let refus;
      try {
        refus = await controle(params);
      } catch (err) {
        // Ne pas savoir est un REFUS, jamais un laissez-passer : `gh` muet ou
        // réseau tombé ne doit pas ouvrir la fusion.
        return send(res, 503, { error: `précondition invérifiable — ${err.message}` });
      }
      if (refus) return send(res, refus.code, { error: refus.message });
    }

    return stream(res, argv, bin);
  }

  send(res, 404, { error: 'not found' });
});

/** L'interface d'écoute. **127.0.0.1 par défaut, et ce défaut est le garde-fou
 *  numéro un** : ce serveur lance des processus, publie sur le CDN et pousse des
 *  branches — il n'a rien à faire sur un réseau.
 *
 *  Réglable uniquement pour le conteneur, qui doit écouter sur l'interface du
 *  CONTENEUR (`0.0.0.0`) pour que Docker puisse lui parler. C'est alors
 *  l'adresse de PUBLICATION du port qui porte la protection, et
 *  `docker/compose.yml` la fixe à `127.0.0.1`.
 *
 *  Vérifié le 2026-08-08 sous Colima : l'adresse de publication est bien
 *  honorée — le forwarder n'écoute que sur `127.0.0.1`, et le port est refusé
 *  depuis le réseau local. Mais c'est une propriété du MOTEUR, pas du code, et
 *  elle change avec lui : `docker/verifier-exposition.sh` la mesure au lieu de
 *  la supposer, en essayant d'atteindre la console depuis l'adresse LAN. */
const HOST = process.env.HOST ?? '127.0.0.1';

server.listen(PORT, HOST, () => {
  const { brouillons } = cartesInstantanees();
  console.log(`Console de pilotage  ->  http://${HOST}:${PORT}`);
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
