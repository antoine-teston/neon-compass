// Le modèle de disposition de la console : quelle section, dans quel onglet,
// dans quelle colonne, dans quel ordre, et laquelle est repliée.
//
// Ce fichier ne connaît PAS le DOM. Il reçoit la liste des sections réellement
// présentes et rend un rangement — ce qui le rend testable sans navigateur, et
// c'est important parce que la règle intéressante n'est pas le glisser-déposer,
// c'est la réconciliation.
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI LA RÉCONCILIATION EXISTE
//
// Le jour où une section est ajoutée à la console, une disposition déjà
// mémorisée ne la connaît pas. Sans réconciliation, elle **n'apparaîtrait
// jamais** chez quiconque a rangé sa page une fois — et rien ne le signalerait.
// C'est la panne silencieuse habituelle de ce dépôt : la chaîne réussit et ne
// montre rien.
//
// Symétriquement, une section retirée du code laisserait un identifiant orphelin
// dans le rangement mémorisé, et une case vide dans la page.
//
// D'où la règle : **le code fait autorité sur ce qui EXISTE, le rangement
// mémorisé ne fait autorité que sur l'ORDRE.**

/** Clé de persistance. Versionnée : changer la FORME de l'objet impose de
 *  changer la clé, sinon un ancien rangement serait relu comme un nouveau.
 *  Passée en v2 le 2026-08-07 avec l'arrivée des onglets. */
export const CLE = 'neon-compass-console-disposition-v2';

/**
 * Les onglets, dans l'ordre. Le découpage suit ce qu'on FAIT, pas ce que les
 * sections sont : on ouvre la console pour relire des brouillons, ou pour
 * lancer une récolte, ou pour éteindre un incendie — rarement pour les trois.
 */
export const ONGLETS = [
  { id: 'revue', label: 'Revue' },
  { id: 'veille', label: 'Veille' },
  { id: 'controles', label: 'Contrôles' },
  { id: 'pilotage', label: 'Pilotage' },
];

/** Le rangement d'origine. C'est aussi la carte qui dit où atterrit une section
 *  neuve — mieux qu'un « à la fin du dernier onglet », qui la mettrait
 *  n'importe où.
 *
 *  `sortie` n'y figure pas, et c'est délibéré : elle vit hors des onglets, tout
 *  en bas, parce qu'elle porte le résultat de ce qu'on vient de lancer. La faire
 *  disparaître en changeant d'onglet serait reprendre d'une main ce qu'on venait
 *  de corriger. */
export const DEFAUT = {
  onglets: {
    revue: [['atelier'], ['graphes']],
    veille: [['recolte'], ['local']],
    controles: [['checks'], ['inventaire']],
    pilotage: [['carnet'], ['prod', 'moderation']],
  },
  replies: [],
};

export const NB_COLONNES = 2;
const IDS_ONGLETS = ONGLETS.map((o) => o.id);

/** L'onglet et la colonne où le défaut place une section, ou `null`. */
function origineDe(id) {
  for (const onglet of IDS_ONGLETS) {
    const colonne = DEFAUT.onglets[onglet].findIndex((c) => c.includes(id));
    if (colonne !== -1) return { onglet, colonne };
  }
  return null;
}

/** Une disposition a-t-elle la forme attendue ? Tout ce qui n'est pas
 *  reconnaissable est jeté sans discussion : un rangement corrompu ne mérite pas
 *  qu'on devine ce qu'il voulait dire. */
function formeValide(d) {
  if (!d || typeof d !== 'object' || !d.onglets || typeof d.onglets !== 'object') return false;
  return IDS_ONGLETS.every((onglet) => {
    const colonnes = d.onglets[onglet];
    return Array.isArray(colonnes)
      && colonnes.length === NB_COLONNES
      && colonnes.every((c) => Array.isArray(c) && c.every((id) => typeof id === 'string'));
  });
}

const vide = () => Object.fromEntries(IDS_ONGLETS.map((o) => [o, [[], []]]));

/**
 * Fond le rangement mémorisé avec ce que le code connaît réellement.
 *
 * Trois garanties, et ce sont elles qu'on teste :
 *
 *   1. toute section connue apparaît EXACTEMENT une fois, tous onglets confondus ;
 *   2. une section connue absente du mémorisé rejoint son onglet et sa colonne
 *      d'origine ;
 *   3. un identifiant inconnu disparaît.
 *
 * @param {unknown} memorise ce qui sortait de localStorage — potentiellement
 *   n'importe quoi, y compris `null` ou du JSON d'une version antérieure.
 * @param {string[]} connus les `data-panneau` réellement présents dans la page.
 */
export function reconcilier(memorise, connus) {
  const existe = new Set(connus);
  const base = formeValide(memorise) ? memorise : DEFAUT;

  const place = new Set();
  const onglets = vide();
  for (const onglet of IDS_ONGLETS) {
    onglets[onglet] = base.onglets[onglet].map((colonne) =>
      colonne.filter((id) => {
        // `place` sert aussi de dédoublonneur : un rangement bricolé à la main
        // pourrait citer deux fois le même identifiant, ce qui afficherait la
        // même section dans deux onglets.
        if (!existe.has(id) || place.has(id)) return false;
        place.add(id);
        return true;
      }),
    );
  }

  for (const id of connus) {
    if (place.has(id)) continue;
    // Son origine si le défaut la connaît, sinon la colonne la plus courte du
    // premier onglet — pour qu'une section vraiment nouvelle soit VUE.
    const origine = origineDe(id);
    const onglet = origine?.onglet ?? IDS_ONGLETS[0];
    const colonnes = onglets[onglet];
    const colonne = origine?.colonne
      ?? colonnes.indexOf(colonnes.reduce((a, b) => (a.length <= b.length ? a : b)));
    colonnes[colonne].push(id);
    place.add(id);
  }

  const repliesMemorisees = Array.isArray(base.replies) ? base.replies : [];
  return {
    onglets,
    replies: [...new Set(repliesMemorisees.filter((id) => existe.has(id)))],
  };
}

/** Toutes les sections d'un rangement, à plat. */
export function toutes(disposition) {
  return IDS_ONGLETS.flatMap((o) => disposition.onglets[o].flat());
}

/** L'onglet qui contient une section, ou `null`. */
export function ongletDe(disposition, id) {
  return IDS_ONGLETS.find((o) => disposition.onglets[o].some((c) => c.includes(id))) ?? null;
}

/** Déplace une section, éventuellement vers un autre onglet. Rend une NOUVELLE
 *  disposition — jamais de mutation sur place, pour que l'appelant puisse
 *  comparer l'avant et l'après.
 *
 *  `avant` est l'identifiant devant lequel insérer, ou `null` pour la fin. */
export function deplacer(disposition, id, ongletCible, colonneCible, avant = null) {
  if (!IDS_ONGLETS.includes(ongletCible)) return disposition;
  if (!(colonneCible >= 0 && colonneCible < NB_COLONNES)) return disposition;

  const onglets = Object.fromEntries(
    IDS_ONGLETS.map((o) => [o, disposition.onglets[o].map((c) => c.filter((x) => x !== id))]),
  );
  const cible = onglets[ongletCible][colonneCible];
  const at = avant === null ? -1 : cible.indexOf(avant);
  if (at === -1) cible.push(id);
  else cible.splice(at, 0, id);

  return { ...disposition, onglets };
}

/** Replie ou déplie une section. */
export function basculerRepli(disposition, id) {
  const replies = disposition.replies.includes(id)
    ? disposition.replies.filter((x) => x !== id)
    : [...disposition.replies, id];
  return { ...disposition, replies };
}

/** Déplie TOUT.
 *
 *  Existe parce qu'une section repliée est une omission, et qu'une omission doit
 *  toujours avoir une sortie visible. Le 2026-08-07, neuf clics sur les en-têtes
 *  suffisaient à escamoter les vingt-sept boutons de la console sans qu'aucun
 *  compteur ne le dise. */
export function toutDeplier(disposition) {
  return { ...disposition, replies: [] };
}

// ---------------------------------------------------------------------------
// Géométrie du glissement
//
// Sorties du navigateur à dessein : ce sont elles qui décident où une section
// tombe, donc la partie réellement faillible du geste. Prendre des rectangles en
// argument plutôt que des éléments les rend vérifiables sans navigateur — et
// Playwright n'est pas une dépendance de ce projet.
// ---------------------------------------------------------------------------

/**
 * L'index de la colonne sous l'abscisse `x`, ou **la plus proche** si le pointeur
 * est sorti des deux. Glisser un peu au-delà du bord ne doit pas annuler le
 * geste en silence : l'utilisateur a visé une colonne, on lui donne celle qu'il
 * visait.
 *
 * @param {{left:number,right:number}[]} boites dans l'ordre des colonnes
 */
export function colonneSous(x, boites) {
  if (!boites.length) return 0;
  const dedans = boites.findIndex((b) => x >= b.left && x <= b.right);
  if (dedans !== -1) return dedans;
  const distances = boites.map((b) => Math.min(Math.abs(x - b.left), Math.abs(x - b.right)));
  return distances.indexOf(Math.min(...distances));
}

/**
 * L'index de la section devant laquelle insérer, ou `null` pour « à la fin ».
 *
 * La règle est la moitié : au-dessus du milieu d'une section, on passe devant
 * elle. Comparer au bord haut ferait sauter le repère d'un cran dès qu'on
 * effleure une section ; comparer au milieu donne un geste stable.
 *
 * @param {{top:number,height:number}[]} boites sections VISIBLES, de haut en bas,
 *   celle qu'on déplace exclue — sinon elle servirait de repère à elle-même.
 */
export function insertionAvant(y, boites) {
  const at = boites.findIndex((b) => y < b.top + b.height / 2);
  return at === -1 ? null : at;
}

// ---------------------------------------------------------------------------
// Persistance
// ---------------------------------------------------------------------------

/** Lecture depuis un stockage — `localStorage` en vrai, un objet simulé dans les
 *  tests. Un stockage illisible n'est jamais une erreur fatale : la console doit
 *  s'afficher même si le navigateur refuse le stockage (navigation privée). */
export function lire(stockage, connus) {
  let brut = null;
  try {
    brut = JSON.parse(stockage?.getItem(CLE) ?? 'null');
  } catch {
    brut = null;
  }
  return reconcilier(brut, connus);
}

export function ecrire(stockage, disposition) {
  try {
    stockage?.setItem(CLE, JSON.stringify(disposition));
    return true;
  } catch {
    // Quota plein, navigation privée, stockage désactivé : la disposition reste
    // valable pour la session en cours. Perdre le rangement est ennuyeux ; faire
    // tomber la console pour ça serait absurde.
    return false;
  }
}

export function oublier(stockage) {
  try {
    stockage?.removeItem(CLE);
  } catch {
    /* voir `ecrire` */
  }
}
