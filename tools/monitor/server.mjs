#!/usr/bin/env node
// Le moniteur — la moitié LISIBLE de la console, faite pour tourner ailleurs
// que sur le Mac.
//
//   node tools/monitor/server.mjs            puis ouvrir l'URL affichée
//   PORT=8080 node tools/monitor/server.mjs
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI IL EST SÉPARÉ DE LA CONSOLE, ET PAS UN MODE DE CELLE-CI
//
// La console tient parce qu'elle écoute sur 127.0.0.1 : personne d'autre que
// celui assis devant le Mac ne peut l'atteindre, ce qui lui permet de n'avoir
// aucune authentification tout en sachant publier sur le CDN et lancer des
// migrations.
//
// Ce service-là écoute sur toutes les interfaces, parce qu'il n'aurait aucun
// intérêt sinon : il tourne sur un Raspberry Pi et se regarde depuis un
// téléphone. La protection « personne ne peut appeler » disparaît. Ce qui la
// remplace, c'est qu'IL N'Y A RIEN À APPELER — pas de POST, pas de `spawn`, pas
// de dépôt git, pas de clé `service_role`.
//
// Un mode de la console n'aurait pas donné ça : le code d'écriture serait resté
// présent, à un `if` de distance. Ici il n'est pas dans l'image.
//
// ─────────────────────────────────────────────────────────────────────────────
// CE QU'IL DÉTIENT
//
// Un jeton dont tout le pouvoir est de demander « combien » à la fonction
// `metrics`, qui n'agrège que des nombres. Perdre ce Pi ne donne accès ni à un
// pseudonyme, ni à un titre, ni à quoi que ce soit d'écrivable.

import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { instantane } from './metrics.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT ?? 4322);

/** L'hôte d'écoute. `0.0.0.0` par défaut ici — l'inverse de la console, et
 *  c'est assumé : un moniteur sur un Pi qui n'écouterait que la boucle locale
 *  ne servirait à personne. Reste réglable pour qui veut le limiter à une
 *  interface. */
const HOTE = process.env.HOST ?? '0.0.0.0';

/** Fréquence de rafraîchissement de la page, en secondes.
 *
 *  Trente secondes et non deux : ces nombres ne bougent pas plus vite qu'une
 *  décision humaine, et interroger la fonction en boucle coûterait des
 *  invocations pour redessiner le même graphe. */
export const RAFRAICHIR_S = Number(process.env.REFRESH_SECONDS ?? 30);

/** Liste blanche, comme la console — aucun chemin venu de la requête n'atteint
 *  le disque. `join(ICI, url.pathname)` aurait marché et aurait été faux. */
const FICHIERS = {
  '/': ['index.html', 'text/html'],
  '/graphes.mjs': ['graphes.mjs', 'text/javascript'],
  '/graphes.css': ['graphes.css', 'text/css'],
};

/** Le cache de l'instantané.
 *
 *  Trois raisons, dans cet ordre : ne pas appeler la fonction une fois par
 *  onglet ouvert ; garder la page instantanée ; et surtout, ne pas transformer
 *  un moniteur en générateur de charge sur la production le jour où quelqu'un
 *  laisse un onglet ouvert sur un mur. */
let cache = { a: 0, valeur: null };
const CACHE_MS = 15_000;

async function lire(maintenant) {
  if (cache.valeur && maintenant - cache.a < CACHE_MS) return cache.valeur;
  const valeur = await instantane(process.env);
  cache = { a: maintenant, valeur };
  return valeur;
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  // Une seule méthode. Tout le reste est refusé avant même de regarder le
  // chemin : c'est la phrase qui résume ce service.
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { allow: 'GET, HEAD', 'content-type': 'application/json' });
    return res.end(JSON.stringify({ error: 'le moniteur ne fait que lire' }));
  }

  if (FICHIERS[url.pathname]) {
    const [fichier, type] = FICHIERS[url.pathname];
    res.writeHead(200, { 'content-type': `${type}; charset=utf-8`, 'cache-control': 'no-store' });
    return res.end(readFileSync(join(ICI, fichier), 'utf8'));
  }

  if (url.pathname === '/api/metrics') {
    const valeur = await lire(Date.now());
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    return res.end(JSON.stringify({ ...valeur, rafraichirS: RAFRAICHIR_S }));
  }

  // La sonde de santé du conteneur. Elle répond 200 tant que le PROCESSUS vit —
  // elle ne teste PAS Supabase à dessein : un redémarrage en boucle parce que le
  // réseau est tombé remplacerait un tableau de bord qui dit « injoignable »
  // par un conteneur qui ne dit plus rien du tout.
  if (url.pathname === '/sante') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ ok: true }));
  }

  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
});

server.listen(PORT, HOTE, () => {
  console.log(`Moniteur Neon Compass  ->  http://${HOTE}:${PORT}`);
  // Dire tout de suite si le jeton manque : découvrir une configuration
  // incomplète en regardant un écran à l'autre bout de la maison coûte cher.
  if (!process.env.MONITOR_TOKEN) {
    console.log('  MONITOR_TOKEN absent — la page dira pourquoi elle ne montre rien');
  }
});
