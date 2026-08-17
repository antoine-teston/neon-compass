// La date de MISE EN LIGNE d'une actu, par opposition à la date de l'information.
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI DEUX DATES
//
// `publishedAt` porte la date de l'ARTICLE SOURCE : `facts-to-news.mjs` la
// recopie de `source_date`, et elle ne bouge plus jamais. C'est la bonne date à
// AFFICHER — un démenti paru le 10 août est daté du 10 août, et le lecteur peut
// ouvrir la source pour le vérifier.
//
// Mais ce n'est pas la date à laquelle l'entrée est apparue DANS L'APP. Entre la
// récolte et la publication, il se passe des jours : au 2026-08-17, cinq actus
// datées des 10, 11 et 14 août sont parties au CDN le même matin, dont une avec
// sept jours d'écart. Triées sur `publishedAt`, elles arrivaient enterrées sous
// des entrées que le lecteur avait déjà vues.
//
// D'où ce second champ, qui répond à « quand est-ce apparu chez le lecteur ? ».
// Le fil TRIE dessus et affiche l'autre.
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI L'ESTAMPILLE EST POSÉE ICI, ET PAS DANS LA CONSOLE
//
// Le clic « Publier » de la console n'est pas le moment de la mise en ligne : il
// écrit `status: published` dans l'arbre de travail, et le contenu ne part au
// CDN qu'au merge sur `main`, par le job `publish-news`. Estampiller au clic
// n'aurait fait que DÉPLACER le décalage — la commande tourne donc dans ce job,
// juste avant `release`, pour que le fragment téléversé porte déjà sa date.
//
// Conséquence à ne pas perdre : cette commande ÉCRIT dans `content/`, et son
// résultat doit être recommité sur `main`. C'est le même aller-retour que le
// verrou de versions, et il se fait dans le même commit.

/** Le seul kind concerné. Les événements en ligne s'ordonnent sur `startsAt`,
 *  qui est déjà une date d'apparition ; les POI et les cheats n'ont pas de fil. */
const KIND = 'news';

/** Une estampille absente, vide ou blanche vaut absente.
 *
 *  La forme n'est pas vérifiée ici : c'est `validate` qui tient le format des
 *  dates, et une estampille malformée doit rougir la CI plutôt que d'être
 *  silencieusement réécrite — la réécrire masquerait le bug qui l'a produite. */
function sansEstampille(data) {
  return typeof data.listedAt !== 'string' || data.listedAt.trim() === '';
}

/** Range `listedAt` juste après `publishedAt` plutôt qu'en fin d'objet.
 *
 *  Le diff d'une publication est relu à la main : les deux dates doivent se
 *  lire l'une sous l'autre. Un objet sans `publishedAt` — que le schéma
 *  interdit — reçoit la clé en fin plutôt que de faire lever : refuser ici
 *  ferait échouer la publication du LOT entier pour un fichier que `validate`
 *  aurait déjà dû arrêter. */
function avecEstampille(data, jour) {
  if (!('publishedAt' in data)) return { ...data, listedAt: jour };
  const range = {};
  for (const [cle, valeur] of Object.entries(data)) {
    range[cle] = valeur;
    if (cle === 'publishedAt') range.listedAt = jour;
  }
  return range;
}

/**
 * Ce qui est à estampiller, et rien d'autre.
 *
 * Pure : ni disque, ni horloge — le jour est un paramètre. C'est ce qui rend
 * l'idempotence éprouvable, et l'idempotence EST l'invariant du chantier : sans
 * elle, chaque publication réestampillerait tout le fil à la date du jour, et
 * l'ordre d'arrivée qu'on cherche à établir serait détruit à chaque merge.
 *
 * @param {{kind: string, file: string, data: object}[]} entries  l'arbre chargé
 * @param {string} jour  la date de la mise en ligne, en AAAA-MM-JJ
 * @returns {{file: string, data: object}[]}  les entrées MODIFIÉES, copiées
 */
export function aEstampiller(entries, jour) {
  return entries
    .filter(({ kind, data }) => kind === KIND && data.status === 'published' && sansEstampille(data))
    .map(({ file, data }) => ({ file, data: avecEstampille(data, jour) }));
}

/** Le jour courant en UTC, au format du champ.
 *
 *  UTC et non le fuseau de la machine : la commande tourne sur un runner CI, et
 *  une date qui dépendrait du fuseau donnerait deux résultats différents selon
 *  l'endroit d'où on relance la même publication. */
export function jourUTC(maintenant = new Date()) {
  return maintenant.toISOString().slice(0, 10);
}
