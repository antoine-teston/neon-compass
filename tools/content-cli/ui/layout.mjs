// Le modèle de disposition de la console : quelles sections, dans quelle
// colonne, dans quel ordre, et lesquelles sont repliées.
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
 *  changer la clé, sinon un ancien rangement serait relu comme un nouveau. */
export const CLE = 'neon-compass-console-disposition-v1';

/**
 * Le rangement d'origine. C'est aussi la carte qui dit où atterrit une section
 * neuve — mieux qu'un « à la fin de la dernière colonne », qui la mettrait
 * n'importe où.
 */
export const DEFAUT = {
  colonnes: [
    ['atelier', 'recolte', 'checks', 'local'],
    ['carnet', 'sortie', 'prod', 'moderation', 'inventaire'],
  ],
  replies: [],
};

export const NB_COLONNES = DEFAUT.colonnes.length;

/** La colonne où le défaut place une section, ou `null` s'il ne la connaît pas. */
function colonneDorigine(id) {
  const index = DEFAUT.colonnes.findIndex((c) => c.includes(id));
  return index === -1 ? null : index;
}

/** Une disposition a-t-elle la forme attendue ? Tout ce qui n'est pas
 *  reconnaissable est jeté sans discussion : un rangement corrompu ne mérite pas
 *  qu'on devine ce qu'il voulait dire. */
function formeValide(d) {
  return Boolean(
    d
    && typeof d === 'object'
    && Array.isArray(d.colonnes)
    && d.colonnes.length === NB_COLONNES
    && d.colonnes.every((c) => Array.isArray(c) && c.every((id) => typeof id === 'string')),
  );
}

/**
 * Fond le rangement mémorisé avec ce que le code connaît réellement.
 *
 * Trois garanties, et ce sont elles qu'on teste :
 *
 *   1. toute section connue apparaît EXACTEMENT une fois ;
 *   2. une section connue absente du mémorisé rejoint sa colonne d'origine ;
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
  const colonnes = base.colonnes.map((colonne) =>
    colonne.filter((id) => {
      // `place` sert aussi de dédoublonneur : un rangement bricolé à la main
      // pourrait citer deux fois le même identifiant, ce qui déplacerait la même
      // section dans deux colonnes.
      if (!existe.has(id) || place.has(id)) return false;
      place.add(id);
      return true;
    }),
  );

  for (const id of connus) {
    if (place.has(id)) continue;
    // Sa colonne d'origine si le défaut la connaît, sinon la plus courte — pour
    // qu'une section vraiment nouvelle n'aggrave pas le déséquilibre.
    const cible = colonneDorigine(id)
      ?? colonnes.indexOf(colonnes.reduce((a, b) => (a.length <= b.length ? a : b)));
    colonnes[cible].push(id);
    place.add(id);
  }

  const repliesMemorisees = Array.isArray(base.replies) ? base.replies : [];
  return {
    colonnes,
    replies: [...new Set(repliesMemorisees.filter((id) => existe.has(id)))],
  };
}

/** Déplace une section. Rend une NOUVELLE disposition — jamais de mutation sur
 *  place, pour que l'appelant puisse comparer l'avant et l'après.
 *
 *  `avant` est l'identifiant devant lequel insérer, ou `null` pour la fin. */
export function deplacer(disposition, id, colonneCible, avant = null) {
  const colonnes = disposition.colonnes.map((c) => c.filter((x) => x !== id));
  const cible = colonnes[colonneCible];
  if (!cible) return disposition;

  const at = avant === null ? -1 : cible.indexOf(avant);
  if (at === -1) cible.push(id);
  else cible.splice(at, 0, id);

  return { ...disposition, colonnes };
}

/** Replie ou déplie une section. */
export function basculerRepli(disposition, id) {
  const replies = disposition.replies.includes(id)
    ? disposition.replies.filter((x) => x !== id)
    : [...disposition.replies, id];
  return { ...disposition, replies };
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
