// Le vocabulaire pur de la veille : CONFIANCE_ORDRE, CARDINALITE et
// HORS_CONTROLE — trois tables de constantes, sans schéma JSON ni disque
// derrière elles.
//
// Elles vivaient dans `schemas.mjs`, à côté des schémas. Mais `schemas.mjs`
// lit cinq fichiers `.schema.json` et compile AJV en haut du module (voir
// `rawSchemas`/`compiled`) — et `facts-to-news.mjs` promet dans son en-tête de
// n'exécuter AUCUNE I/O. Lui faire importer `CARDINALITE` depuis
// `schemas.mjs` rendait cette promesse fausse : charger une transformation
// pure déclenchait cinq `readFileSync` et une compilation ajv qu'elle
// n'utilise jamais.
//
// Ces trois tables sont des faits du domaine, pas des dérivés des schémas
// compilés : rien ici ne lit le disque, et rien ne doit y être ajouté qui le
// fasse. Ne les rapatrie pas dans `schemas.mjs` — ce serait recréer le
// couplage que ce fichier existe pour casser.

/** L'échelle de confiance, du plus FAIBLE au plus FORT.
 *
 *  L'énumération de `news.schema.json` la donne dans l'ordre inverse ; un test
 *  compare les deux ENSEMBLES, pour qu'ajouter un niveau au schéma fasse tomber
 *  la suite au lieu de créer une comparaison muette. */
export const CONFIANCE_ORDRE = ['rumor', 'single-source', 'multi-source', 'confirmed-official'];

/** Combien d'entrées une même URL source a le droit de produire, par kind.
 *
 *  `une` déclenche le contrôle de convergence ; `multiple` l'éteint. Les POI le
 *  sont parce qu'un article « toutes les localisations confirmées » en donne
 *  légitimement trois — c'est ainsi que les 537 POI sont arrivés. */
export const CARDINALITE = {
  news: 'une',
  poi: 'multiple',
  'poi-gtav': 'multiple',
  cheats: 'multiple',
  collections: 'multiple',
};

/** Les kinds que le contrôle d'URL ne juge PAS, et pourquoi.
 *
 *  Deux tables plutôt qu'un défaut : inscrire `online-events` dans
 *  `CARDINALITE` suggérerait qu'il est couvert par ce contrôle-ci alors qu'il
 *  l'est par le sien ; le taire laisserait croire à un oubli. */
export const HORS_CONTROLE = {
  'online-events':
    'identité portée par windowDiscriminant (début de fenêtre), déjà insensible au claim',
};
