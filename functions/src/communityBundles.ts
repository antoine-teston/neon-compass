// Logique pure de la mise en fragments des spots communautaires — pas de
// Firestore, pas d'horloge, pas d'I/O. Ce qui décide vit ici, les deux
// Functions ne font qu'exécuter. Testable avec node:test, sans émulateur,
// comme contribution.ts et vote.ts.

/** Valeur de `collection` portée par les fragments, et clé du cache client. */
export const BUNDLE_COLLECTION = 'community_spots';

/** Document unique qui porte la version. Le client ne lit que lui quand rien
 *  n'a changé : une lecture par lancement, contre toute la collection avant. */
export const MANIFEST_ID = 'community_spots_manifest';

/** Aligné sur `ContentBundle.chunkSize` côté Swift et `BUNDLE_CHUNK_SIZE` dans
 *  le CLI. La valeur est dupliquée aux trois endroits, donc toute dérive doit
 *  se voir — d'où le test qui la fige. */
export const CHUNK_SIZE = 500;

/** Reconstruction forcée passé ce délai, même si rien n'est « sale ».
 *
 *  Sans elle les compteurs de votes seraient figés à jamais : un vote ne salit
 *  délibérément pas le manifeste (voir `isDirtyingChange`), sinon le pic de
 *  votes déclencherait une reconstruction complète en continu — exactement au
 *  moment où on ne peut pas se le permettre. Une heure de fraîcheur sur un
 *  compteur est un compromis acceptable, d'autant que le client applique déjà
 *  ses propres votes de façon optimiste. */
export const FORCED_REBUILD_INTERVAL_MS = 60 * 60 * 1000;

/** Champs dont un changement modifie ce que les clients voient. `upvotes` et
 *  `downvotes` en sont volontairement absents. */
export const MEMBERSHIP_FIELDS = [
  'status',
  'shadowHidden',
  'position',
  'title',
  'category',
  'authorHandle',
] as const;

type Doc = Record<string, unknown> | undefined;

/** Un écrit sur `contributions` doit-il marquer les fragments périmés ?
 *
 *  Création et suppression : toujours. Modification : seulement si l'un des
 *  champs d'appartenance a bougé. */
export function isDirtyingChange(before: Doc, after: Doc): boolean {
  if (!before || !after) return true;
  return MEMBERSHIP_FIELDS.some(
    (field) => JSON.stringify(before[field] ?? null) !== JSON.stringify(after[field] ?? null)
  );
}

export interface Manifest {
  version?: number;
  chunks?: number;
  dirty?: boolean;
  builtAtMs?: number;
}

/** Faut-il reconstruire maintenant ? Pas de manifeste = jamais construit. */
export function shouldRebuild(manifest: Manifest | undefined, nowMs: number): boolean {
  if (!manifest) return true;
  if (manifest.dirty) return true;
  const builtAtMs = manifest.builtAtMs ?? 0;
  return nowMs - builtAtMs >= FORCED_REBUILD_INTERVAL_MS;
}

/** Un spot visible publiquement.
 *
 *  `shadowHidden` est filtré ICI, côté application : le client ne lit plus la
 *  collection `contributions`, donc la Security Rule qui portait ce filtre ne
 *  protège plus rien sur ce chemin. C'est le point de vigilance du chantier.
 *
 *  Ce n'était le SEUL point de filtrage que jusqu'au classement des
 *  contributeurs : `leaderboard.ts::tallyApproved` applique la même règle sur
 *  son propre chemin d'agrégation. Les deux sont d'accord, et volontairement
 *  séparés — celui-ci décide ce qui s'affiche sur la carte, l'autre ce qui
 *  compte au classement. Un troisième chemin devrait rejoindre cette liste
 *  plutôt que de la contredire en silence. */
export function isPubliclyVisible(doc: Record<string, unknown>): boolean {
  return doc.status === 'approved' && doc.shadowHidden !== true;
}

/** Projection d'un document `contributions` vers ce qu'un fragment porte.
 *
 *  Explicite plutôt qu'un `...doc` : un champ ajouté côté serveur ne doit pas
 *  partir vers les clients par accident, et les clés doivent rester exactement
 *  celles que `Contribution` décode côté Swift. */
export function bundleItem(id: string, doc: Record<string, unknown>) {
  return {
    id,
    authorUid: doc.authorUid ?? null,
    authorHandle: doc.authorHandle,
    category: doc.category,
    title: doc.title,
    languageCode: doc.languageCode,
    position: doc.position,
    status: doc.status,
    upvotes: doc.upvotes ?? 0,
    downvotes: doc.downvotes ?? 0,
  };
}

export function chunked<T>(items: T[], size: number = CHUNK_SIZE): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  // Une collection vide produit UN fragment vide plutôt qu'aucun : sans lui, le
  // dernier fragment d'une collection qui se vide resterait en ligne, et les
  // clients continueraient de lire des spots retirés.
  return out.length ? out : [[]];
}
