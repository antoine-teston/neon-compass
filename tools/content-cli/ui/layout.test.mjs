// node --test tools/content-cli/ui/layout.test.mjs
//
// La règle que ces tests protègent : **le code fait autorité sur ce qui EXISTE,
// le rangement mémorisé ne fait autorité que sur l'ORDRE.**
//
// Sans elle, ajouter une section à la console la rendrait invisible chez
// quiconque a rangé sa page une fois — et rien ne le signalerait. C'est la
// panne silencieuse habituelle : la chaîne réussit et ne montre rien.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CLE,
  DEFAUT,
  NB_COLONNES,
  basculerRepli,
  colonneSous,
  deplacer,
  ecrire,
  insertionAvant,
  lire,
  oublier,
  reconcilier,
} from './layout.mjs';

const TOUS = DEFAUT.colonnes.flat();
const aplati = (d) => d.colonnes.flat();

/** Un `localStorage` de laboratoire. */
function stockage(initial = {}) {
  const data = { ...initial };
  return {
    getItem: (k) => data[k] ?? null,
    setItem: (k, v) => { data[k] = v; },
    removeItem: (k) => { delete data[k]; },
    data,
  };
}

// ---------------------------------------------------------------------------
// Réconciliation — les trois garanties
// ---------------------------------------------------------------------------

test('sans rien de mémorisé, on obtient le rangement par défaut', () => {
  assert.deepEqual(reconcilier(null, TOUS), { colonnes: DEFAUT.colonnes, replies: [] });
});

test('une section NEUVE apparaît, dans sa colonne d’origine', () => {
  // LE test de ce fichier. Le rangement mémorisé date d'avant l'ajout de
  // « sortie » ; sans réconciliation, la section n'existerait plus pour cet
  // utilisateur, sans le moindre message.
  const vieux = {
    colonnes: [['atelier', 'recolte', 'checks', 'local'], ['carnet', 'prod', 'moderation', 'inventaire']],
    replies: [],
  };
  const d = reconcilier(vieux, TOUS);
  assert.ok(aplati(d).includes('sortie'), 'la section neuve a disparu');
  assert.ok(d.colonnes[1].includes('sortie'), 'elle devrait rejoindre sa colonne d’origine');
});

test('une section neuve INCONNUE du défaut rejoint la colonne la plus courte', () => {
  const memorise = { colonnes: [['atelier'], ['carnet', 'prod', 'moderation']], replies: [] };
  const d = reconcilier(memorise, ['atelier', 'carnet', 'prod', 'moderation', 'inedit']);
  assert.ok(d.colonnes[0].includes('inedit'), JSON.stringify(d.colonnes));
});

test('un identifiant qui n’existe plus est retiré', () => {
  const memorise = {
    colonnes: [['atelier', 'sectionSupprimee'], ['carnet']],
    replies: ['sectionSupprimee'],
  };
  const d = reconcilier(memorise, ['atelier', 'carnet']);
  assert.equal(aplati(d).includes('sectionSupprimee'), false);
  assert.equal(d.replies.includes('sectionSupprimee'), false);
});

test('toute section connue apparaît exactement une fois', () => {
  const bricole = {
    colonnes: [['atelier', 'carnet', 'atelier'], ['carnet', 'recolte']],
    replies: [],
  };
  const d = reconcilier(bricole, TOUS);
  const ids = aplati(d);
  assert.equal(new Set(ids).size, ids.length, 'un doublon a survécu');
  assert.deepEqual([...ids].sort(), [...TOUS].sort(), 'une section manque ou est en trop');
});

test('l’ordre mémorisé est respecté', () => {
  const inverse = {
    colonnes: [['local', 'checks', 'recolte', 'atelier'], ['inventaire', 'moderation', 'prod', 'sortie', 'carnet']],
    replies: [],
  };
  assert.deepEqual(reconcilier(inverse, TOUS).colonnes, inverse.colonnes);
});

test('un rangement corrompu retombe sur le défaut, sans deviner', () => {
  const corrompus = [
    undefined,
    42,
    'texte',
    {},
    { colonnes: 'pas un tableau' },
    { colonnes: [] },
    { colonnes: [['a']] },                       // mauvais nombre de colonnes
    { colonnes: [['a'], ['b'], ['c']] },         // idem
    { colonnes: [[1, 2], ['b']] },               // pas des chaînes
    { colonnes: [null, null] },
  ];
  for (const c of corrompus) {
    assert.deepEqual(
      reconcilier(c, TOUS).colonnes,
      DEFAUT.colonnes,
      `mal rattrapé : ${JSON.stringify(c)}`,
    );
  }
});

test('le nombre de colonnes ne change jamais', () => {
  for (const entree of [null, { colonnes: [['atelier']], replies: [] }]) {
    assert.equal(reconcilier(entree, TOUS).colonnes.length, NB_COLONNES);
  }
});

// ---------------------------------------------------------------------------
// Déplacement et repli
// ---------------------------------------------------------------------------

test('déplacer une section d’une colonne à l’autre ne la duplique pas', () => {
  const d = deplacer(reconcilier(null, TOUS), 'atelier', 1);
  assert.equal(d.colonnes[0].includes('atelier'), false);
  assert.equal(d.colonnes[1].filter((x) => x === 'atelier').length, 1);
  assert.deepEqual([...aplati(d)].sort(), [...TOUS].sort());
});

test('déplacer devant une section précise l’insère au bon rang', () => {
  const d = deplacer(reconcilier(null, TOUS), 'inventaire', 0, 'recolte');
  assert.deepEqual(d.colonnes[0], ['atelier', 'inventaire', 'recolte', 'checks', 'local']);
});

test('déplacer sans repère met en fin de colonne', () => {
  const d = deplacer(reconcilier(null, TOUS), 'atelier', 0);
  assert.equal(d.colonnes[0].at(-1), 'atelier');
});

test('déplacer devant une section absente met en fin, plutôt que d’échouer', () => {
  const d = deplacer(reconcilier(null, TOUS), 'atelier', 1, 'nexistepas');
  assert.equal(d.colonnes[1].at(-1), 'atelier');
});

test('une colonne inexistante laisse la disposition intacte', () => {
  const avant = reconcilier(null, TOUS);
  assert.deepEqual(deplacer(avant, 'atelier', 7), avant);
});

test('déplacer ne mute pas la disposition d’entrée', () => {
  const avant = reconcilier(null, TOUS);
  const copie = JSON.parse(JSON.stringify(avant));
  deplacer(avant, 'atelier', 1);
  assert.deepEqual(avant, copie, 'la disposition d’origine a été modifiée sur place');
});

test('le repli est une bascule, et ne mute pas non plus', () => {
  const a = reconcilier(null, TOUS);
  const b = basculerRepli(a, 'inventaire');
  assert.deepEqual(b.replies, ['inventaire']);
  assert.deepEqual(basculerRepli(b, 'inventaire').replies, []);
  assert.deepEqual(a.replies, [], 'la disposition d’origine a été modifiée sur place');
});

// ---------------------------------------------------------------------------
// Persistance
// ---------------------------------------------------------------------------

test('un aller-retour par le stockage conserve le rangement', () => {
  const s = stockage();
  const range = deplacer(basculerRepli(reconcilier(null, TOUS), 'inventaire'), 'sortie', 0, 'checks');
  ecrire(s, range);
  assert.deepEqual(lire(s, TOUS), range);
});

test('un stockage contenant du JSON invalide ne fait pas tomber la console', () => {
  assert.deepEqual(lire(stockage({ [CLE]: '{{{ pas du json' }), TOUS).colonnes, DEFAUT.colonnes);
});

test('un stockage qui refuse d’écrire ne lève pas', () => {
  // Navigation privée, quota plein, stockage désactivé : perdre le rangement est
  // ennuyeux ; faire tomber la console pour ça serait absurde.
  const refus = { getItem: () => null, setItem: () => { throw new Error('quota'); }, removeItem: () => { throw new Error('non'); } };
  assert.equal(ecrire(refus, DEFAUT), false);
  assert.doesNotThrow(() => oublier(refus));
  assert.doesNotThrow(() => lire(refus, TOUS));
});

test('oublier ramène au défaut', () => {
  const s = stockage();
  ecrire(s, deplacer(reconcilier(null, TOUS), 'atelier', 1));
  oublier(s);
  assert.deepEqual(lire(s, TOUS).colonnes, DEFAUT.colonnes);
});

// ---------------------------------------------------------------------------
// Géométrie du glissement
//
// C'est la partie qui décide où une section tombe, donc celle qu'on a le plus de
// chances de rater. Elle prend des rectangles et rend des index : pas besoin de
// navigateur, et Playwright n'est pas une dépendance de ce projet.
// ---------------------------------------------------------------------------

const COLONNES = [{ left: 0, right: 700 }, { left: 730, right: 1430 }];

test('le pointeur dans une colonne désigne cette colonne', () => {
  assert.equal(colonneSous(350, COLONNES), 0);
  assert.equal(colonneSous(1000, COLONNES), 1);
  assert.equal(colonneSous(0, COLONNES), 0, 'le bord gauche appartient à la colonne');
  assert.equal(colonneSous(1430, COLONNES), 1, 'le bord droit aussi');
});

test('le pointeur entre deux colonnes prend la plus proche', () => {
  assert.equal(colonneSous(710, COLONNES), 0);
  assert.equal(colonneSous(725, COLONNES), 1);
});

test('le pointeur hors de tout prend la colonne la plus proche, jamais rien', () => {
  // Glisser un peu au-delà du bord ne doit pas annuler le geste en silence :
  // l'utilisateur a visé une colonne, on lui donne celle qu'il visait.
  assert.equal(colonneSous(-500, COLONNES), 0);
  assert.equal(colonneSous(9999, COLONNES), 1);
});

test('sans colonne, la géométrie ne lève pas', () => {
  assert.equal(colonneSous(100, []), 0);
});

const SECTIONS = [
  { top: 0, height: 100 },     // milieu à 50
  { top: 120, height: 100 },   // milieu à 170
  { top: 240, height: 100 },   // milieu à 290
];

test('au-dessus du milieu d’une section, on passe devant elle', () => {
  assert.equal(insertionAvant(10, SECTIONS), 0);
  assert.equal(insertionAvant(49, SECTIONS), 0);
  assert.equal(insertionAvant(51, SECTIONS), 1, 'passé le milieu, on vise la suivante');
  assert.equal(insertionAvant(200, SECTIONS), 2);
});

test('sous le dernier milieu, on insère à la fin', () => {
  assert.equal(insertionAvant(291, SECTIONS), null);
  assert.equal(insertionAvant(99999, SECTIONS), null);
});

test('une colonne vide insère à la fin', () => {
  assert.equal(insertionAvant(42, []), null);
});

test('le repère bascule au MILIEU, pas au bord', () => {
  // Comparer au bord haut ferait sauter le repère d'un cran dès qu'on effleure
  // une section — le geste deviendrait nerveux et imprévisible.
  const [s] = SECTIONS;
  const milieu = s.top + s.height / 2;
  assert.equal(insertionAvant(milieu - 1, SECTIONS), 0);
  assert.equal(insertionAvant(milieu + 1, SECTIONS), 1);
});

test('la clé est versionnée', () => {
  // Changer la FORME de l'objet sans changer la clé ferait relire un ancien
  // rangement comme un nouveau. `formeValide` rattraperait la plupart des cas,
  // mais pas celui d'une forme restée superficiellement compatible.
  assert.match(CLE, /-v\d+$/);
});
