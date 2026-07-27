// Construction du site statique de contenu — la version CDN de ce que
// `pushBundles` écrit dans Firestore.
//
// Pourquoi un CDN plutôt qu'une base : le trafic de cette app est à 95 % de la
// lecture de contenu partagé et versionné. Ce n'est pas une charge de base de
// données, c'est de la distribution de fichiers. Un JSON derrière une URL coûte
// zéro par lecture (contre une lecture facturée par document), répond depuis le
// cache en périphérie plutôt que depuis `eur3`, et surtout **ne demande aucun
// SDK** : Swift, Kotlin et un navigateur le lisent identiquement. C'est ce
// dernier point qui compte si un second client existe un jour.
//
// Fonction pure, aucune I/O : `cli.js` écrit ce qu'on lui rend.

/** Doit rester aligné sur `ContentBundle.chunkSize` côté Swift et
 *  `BUNDLE_CHUNK_SIZE` dans `firestore-client.js`. Dupliqué aux trois endroits,
 *  donc toute dérive doit se voir — un test la fige. */
export const CHUNK_SIZE = 500;

export function chunked(items, size = CHUNK_SIZE) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  // Une collection vide produit UN fragment vide plutôt qu'aucun : sinon le
  // dernier fragment d'une collection qui se vide resterait servi par le CDN,
  // et les clients continueraient de lire du contenu retiré.
  return out.length ? out : [[]];
}

/**
 * @param entries  [{ kind, data }] tels que `loadAll()` les produit
 * @param kinds    la table KINDS du CLI : kind -> { collection }
 * @param version  entier monotone, celui que les clients comparent
 * @param commit   SHA publié, pour répondre à « quel contenu est en ligne ? »
 * @returns [{ path, json, immutable }] — l'arborescence à écrire, chemins relatifs
 *
 * Les fragments vivent sous `content/v<version>/…` : leur chemin change à chaque
 * publication, donc leur contenu ne change JAMAIS pour une URL donnée. Le CDN
 * peut les garder un an, et aucun client ne peut recevoir un fragment périmé.
 * Seul le manifeste est court-caché — c'est lui, et lui seul, qui bouge.
 */
export function buildSite(entries, kinds, { version, commit }) {
  // Seul le `published` part, exactement comme vers Firestore : un brouillon
  // peut dormir dans le dépôt indéfiniment sans jamais atteindre un client.
  const publishable = entries.filter((entry) => entry.data.status === 'published');

  const files = [];
  const collections = {};

  for (const [kind, { collection }] of Object.entries(kinds)) {
    const items = publishable.filter((entry) => entry.kind === kind).map((entry) => entry.data);
    const chunks = chunked(items);
    collections[collection] = { chunks: chunks.length, count: items.length };
    chunks.forEach((chunkItems, chunk) => {
      files.push({
        path: `content/v${version}/${collection}/${chunk}.json`,
        json: { collection, chunk, items: chunkItems },
        immutable: true,
      });
    });
  }

  // Le manifeste porte la version ET la carte des fragments : un client à jour
  // lit ce seul fichier et s'arrête là. C'est l'équivalent CDN de la garde
  // `contentVersion` de Remote Config, en une requête au lieu d'un SDK.
  files.push({
    path: 'content/manifest.json',
    json: { version, commit, collections },
    immutable: false,
  });

  return files;
}
