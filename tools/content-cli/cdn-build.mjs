// Construction du site statique de contenu, publié sur Supabase Storage.
//
// Pourquoi des fichiers plutôt qu'une base : le trafic de cette app est à 95 %
// de la lecture de contenu partagé et versionné. Ce n'est pas une charge de base
// de données, c'est de la distribution de fichiers. Un JSON derrière une URL
// répond depuis le cache en périphérie et **ne demande aucun SDK** : Swift,
// Kotlin et un navigateur le lisent identiquement.
//
// Fonction pure, aucune I/O : `cli.js` écrit ce qu'on lui rend.

import { createHash } from 'node:crypto';

/** Doit rester aligné sur `ContentBundle.chunkSize` côté Swift. Dupliqué des
 *  deux côtés d'une frontière réseau, donc toute dérive doit se voir — un test
 *  la fige. */
export const CHUNK_SIZE = 500;

export function chunked(items, size = CHUNK_SIZE) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  // Une collection vide produit UN fragment vide plutôt qu'aucun : sinon le
  // dernier fragment d'une collection qui se vide resterait servi par le CDN,
  // et les clients continueraient de lire du contenu retiré.
  return out.length ? out : [[]];
}

/** Sérialisation à clés triées, récursivement.
 *
 *  L'empreinte doit dépendre du CONTENU, pas de l'ordre dans lequel les clés
 *  sortent d'un fichier. Sans ça, réenregistrer un JSON avec un autre ordre de
 *  clés produirait une empreinte différente, donc une nouvelle version, donc un
 *  retéléchargement complet pour rien — exactement ce que ce mécanisme existe
 *  pour éviter. */
export function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  if (value && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${stableStringify(value[k])}`).join(',')}}`;
  }
  return JSON.stringify(value) ?? 'null';
}

function digestOf(items) {
  return createHash('sha256').update(stableStringify(items)).digest('hex').slice(0, 16);
}

/**
 * @param entries   [{ kind, data }] tels que `loadAll()` les produit
 * @param kinds     la table KINDS du CLI : kind -> { collection }
 * @param version   entier monotone (nombre de commits), candidat pour toute
 *                  collection qui a changé
 * @param commit    SHA publié, pour répondre à « quel contenu est en ligne ? »
 * @param previous  le verrou de la publication précédente :
 *                  { [collection]: { version, digest } }
 * @returns { files, collections }
 *
 * ## Une version PAR COLLECTION, et pourquoi ça compte
 *
 * La version était globale : une publication d'actu — soit la veille, chaque
 * lundi — faisait retélécharger la totalité du contenu à tous les clients, y
 * compris les 327 Ko de POI que personne n'avait touchés. Le portillon de
 * version prétendait être un delta sans en être un.
 *
 * Chaque collection porte désormais sa propre version, qui n'avance que si son
 * empreinte a bougé. Une collection inchangée garde sa version, donc son chemin,
 * donc le cache du CDN ET celui du client. C'est le principal levier sur
 * l'egress, dont le quota est partagé avec la base et l'authentification.
 *
 * La monotonie tient sans état global : `version` ne fait que croître, et on ne
 * l'attribue qu'aux collections qui changent.
 *
 * Les fragments vivent sous `content/v<versionDeLaCollection>/…` : leur chemin
 * change dès que leur contenu change, et jamais autrement. Le CDN peut donc les
 * garder un an. Seul le manifeste est court-caché — c'est lui, et lui seul, qui
 * bouge à chaque publication.
 */
export function buildSite(entries, kinds, { version, commit, previous = {} }) {
  // Seul le `published` part : un brouillon peut dormir dans le dépôt
  // indéfiniment sans jamais atteindre un client.
  const publishable = entries.filter((entry) => entry.data.status === 'published');

  const files = [];
  const collections = {};

  for (const [kind, { collection }] of Object.entries(kinds)) {
    const items = publishable.filter((entry) => entry.kind === kind).map((entry) => entry.data);
    const digest = digestOf(items);
    const before = previous[collection];

    // Contenu changé ⇒ version STRICTEMENT supérieure. Le `+ 1` n'est pas une
    // précaution décorative : sans lui, deux publications depuis le même commit
    // avec un contenu différent donnaient la même version, donc le MÊME chemin
    // — et les fragments sont servis `immutable` pour un an. Le nouveau contenu
    // n'aurait jamais atteint un client déjà passé par là, et la garde
    // `remoteVersion > localVersion` de ContentStore n'aurait rien vu non plus.
    //
    // Le `Math.max` couvre en prime une histoire git réécrite, qui ferait
    // reculer le nombre de commits : une version qui recule laisserait les
    // clients sur leur cache pour toujours.
    const collectionVersion =
      before && before.digest === digest
        ? before.version
        : Math.max(version, (before?.version ?? 0) + 1);

    const chunks = chunked(items);
    collections[collection] = {
      version: collectionVersion,
      digest,
      chunks: chunks.length,
      count: items.length,
    };

    chunks.forEach((chunkItems, chunk) => {
      files.push({
        path: `content/v${collectionVersion}/${collection}/${chunk}.json`,
        json: { collection, chunk, items: chunkItems },
        immutable: true,
      });
    });
  }

  // Le manifeste porte la carte des fragments ET leur version : un client à jour
  // lit ce seul fichier et s'arrête là. `version` global y reste, pour répondre
  // à « quelle publication est en ligne ? » — le client, lui, ne compare plus
  // que les versions par collection.
  //
  // L'empreinte n'y figure pas : elle sert à décider ici, elle n'apprend rien à
  // un client et n'a aucune raison de partir sur le réseau à chaque session.
  const manifestCollections = Object.fromEntries(
    Object.entries(collections).map(([name, entry]) => [
      name,
      { version: entry.version, chunks: entry.chunks, count: entry.count },
    ])
  );

  files.push({
    path: 'content/manifest.json',
    json: { version, commit, collections: manifestCollections },
    immutable: false,
  });

  return { files, collections };
}
