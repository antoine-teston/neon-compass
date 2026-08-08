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
  ONGLETS,
  basculerRepli,
  colonneSous,
  deplacer,
  ecrire,
  insertionAvant,
  lire,
  ongletDe,
  oublier,
  reconcilier,
  toutDeplier,
  toutes,
} from './layout.mjs';

const IDS = ONGLETS.map((o) => o.id);
const TOUS = IDS.flatMap((o) => DEFAUT.onglets[o].flat());

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
  assert.deepEqual(reconcilier(null, TOUS), { onglets: DEFAUT.onglets, replies: [] });
});

test('une section NEUVE apparaît, dans son onglet et sa colonne d’origine', () => {
  // LE test de ce fichier. Le rangement mémorisé date d'avant l'ajout des
  // graphes ; sans réconciliation, la section n'existerait plus pour cet
  // utilisateur, sans le moindre message.
  const vieux = JSON.parse(JSON.stringify(DEFAUT));
  vieux.onglets.revue[1] = [];                       // « graphes » n'existait pas encore
  const d = reconcilier(vieux, TOUS);
  assert.ok(toutes(d).includes('graphes'), 'la section neuve a disparu');
  assert.equal(ongletDe(d, 'graphes'), 'revue', 'elle devrait rejoindre son onglet d’origine');
  assert.ok(d.onglets.revue[1].includes('graphes'), 'et sa colonne d’origine');
});

test('une section neuve INCONNUE du défaut est placée quand même, et VUE', () => {
  const d = reconcilier(DEFAUT, [...TOUS, 'inedit']);
  assert.ok(toutes(d).includes('inedit'), 'une section sans origine connue a été perdue');
  assert.equal(ongletDe(d, 'inedit'), IDS[0], 'elle doit atterrir dans le premier onglet');
});

test('un identifiant qui n’existe plus est retiré', () => {
  const memorise = JSON.parse(JSON.stringify(DEFAUT));
  memorise.onglets.revue[0].push('sectionSupprimee');
  memorise.replies = ['sectionSupprimee'];
  const d = reconcilier(memorise, TOUS);
  assert.equal(toutes(d).includes('sectionSupprimee'), false);
  assert.equal(d.replies.includes('sectionSupprimee'), false);
});

test('toute section connue apparaît exactement une fois, tous onglets confondus', () => {
  const bricole = JSON.parse(JSON.stringify(DEFAUT));
  bricole.onglets.veille[0].push('atelier');          // déjà dans « revue »
  bricole.onglets.pilotage[1].push('atelier');        // et une troisième fois
  const ids = toutes(reconcilier(bricole, TOUS));
  assert.equal(new Set(ids).size, ids.length, 'un doublon a survécu');
  assert.deepEqual([...ids].sort(), [...TOUS].sort(), 'une section manque ou est en trop');
});

test('l’ordre mémorisé est respecté', () => {
  const range = JSON.parse(JSON.stringify(DEFAUT));
  range.onglets.pilotage[1] = ['moderation', 'prod'];  // inversé
  assert.deepEqual(reconcilier(range, TOUS).onglets.pilotage[1], ['moderation', 'prod']);
});

test('un rangement corrompu retombe sur le défaut, sans deviner', () => {
  const corrompus = [
    undefined, 42, 'texte', {},
    { onglets: 'pas un objet' },
    { onglets: {} },
    { onglets: { revue: [['atelier']] } },                       // onglets manquants
    { onglets: Object.fromEntries(IDS.map((o) => [o, [['a']]])) }, // une seule colonne
    { onglets: Object.fromEntries(IDS.map((o) => [o, [[1], ['b']]])) }, // pas des chaînes
    { colonnes: [['atelier'], ['carnet']] },                     // la forme v1
  ];
  for (const c of corrompus) {
    assert.deepEqual(reconcilier(c, TOUS).onglets, DEFAUT.onglets, `mal rattrapé : ${JSON.stringify(c)}`);
  }
});

test('chaque onglet garde exactement deux colonnes', () => {
  for (const entree of [null, { onglets: { revue: [['atelier']] } }]) {
    const d = reconcilier(entree, TOUS);
    for (const o of IDS) assert.equal(d.onglets[o].length, NB_COLONNES, o);
  }
});

test('la Sortie ne fait pas partie des onglets', () => {
  // Elle porte le résultat de ce qu'on vient de lancer : la faire disparaître en
  // changeant d'onglet reprendrait d'une main ce qu'on venait de corriger.
  assert.equal(TOUS.includes('sortie'), false);
});

// ---------------------------------------------------------------------------
// Déplacement, onglets, repli
// ---------------------------------------------------------------------------

test('déplacer une section vers un autre onglet ne la duplique pas', () => {
  const d = deplacer(reconcilier(null, TOUS), 'atelier', 'pilotage', 0);
  assert.equal(ongletDe(d, 'atelier'), 'pilotage');
  assert.equal(toutes(d).filter((x) => x === 'atelier').length, 1);
  assert.deepEqual([...toutes(d)].sort(), [...TOUS].sort());
});

test('déplacer devant une section précise l’insère au bon rang', () => {
  const d = deplacer(reconcilier(null, TOUS), 'atelier', 'pilotage', 1, 'moderation');
  assert.deepEqual(d.onglets.pilotage[1], ['prod', 'atelier', 'moderation']);
});

test('déplacer sans repère met en fin de colonne', () => {
  const d = deplacer(reconcilier(null, TOUS), 'atelier', 'pilotage', 1);
  assert.equal(d.onglets.pilotage[1].at(-1), 'atelier');
});

test('un onglet ou une colonne inexistants laissent la disposition intacte', () => {
  const avant = reconcilier(null, TOUS);
  assert.deepEqual(deplacer(avant, 'atelier', 'inconnu', 0), avant);
  assert.deepEqual(deplacer(avant, 'atelier', 'revue', 7), avant);
  assert.deepEqual(deplacer(avant, 'atelier', 'revue', -1), avant);
});

test('déplacer ne mute pas la disposition d’entrée', () => {
  const avant = reconcilier(null, TOUS);
  const copie = JSON.parse(JSON.stringify(avant));
  deplacer(avant, 'atelier', 'pilotage', 0);
  assert.deepEqual(avant, copie, 'la disposition d’origine a été modifiée sur place');
});

test('ongletDe rend null pour une section absente', () => {
  assert.equal(ongletDe(reconcilier(null, TOUS), 'sortie'), null);
});

test('le repli est une bascule, et ne mute pas non plus', () => {
  const a = reconcilier(null, TOUS);
  const b = basculerRepli(a, 'inventaire');
  assert.deepEqual(b.replies, ['inventaire']);
  assert.deepEqual(basculerRepli(b, 'inventaire').replies, []);
  assert.deepEqual(a.replies, [], 'la disposition d’origine a été modifiée sur place');
});

test('tout déplier vide les replis, et laisse le rangement intact', () => {
  // Une section repliée est une OMISSION, et une omission doit toujours avoir une
  // sortie visible. Le 2026-08-07, neuf clics escamotaient les 27 boutons de la
  // console sans qu'aucun compteur ne le dise.
  let d = reconcilier(null, TOUS);
  for (const id of TOUS) d = basculerRepli(d, id);
  assert.equal(d.replies.length, TOUS.length);

  const deplie = toutDeplier(d);
  assert.deepEqual(deplie.replies, []);
  assert.deepEqual(deplie.onglets, d.onglets, 'déplier ne doit pas déranger le rangement');
});

// ---------------------------------------------------------------------------
// Géométrie du glissement
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
  const [s] = SECTIONS;
  const milieu = s.top + s.height / 2;
  assert.equal(insertionAvant(milieu - 1, SECTIONS), 0);
  assert.equal(insertionAvant(milieu + 1, SECTIONS), 1);
});

// ---------------------------------------------------------------------------
// Persistance
// ---------------------------------------------------------------------------

test('un aller-retour par le stockage conserve le rangement', () => {
  const s = stockage();
  const range = deplacer(basculerRepli(reconcilier(null, TOUS), 'inventaire'), 'checks', 'revue', 0, 'atelier');
  ecrire(s, range);
  assert.deepEqual(lire(s, TOUS), range);
});

test('un stockage contenant du JSON invalide ne fait pas tomber la console', () => {
  assert.deepEqual(lire(stockage({ [CLE]: '{{{ pas du json' }), TOUS).onglets, DEFAUT.onglets);
});

test('un stockage qui refuse d’écrire ne lève pas', () => {
  const refus = {
    getItem: () => null,
    setItem: () => { throw new Error('quota'); },
    removeItem: () => { throw new Error('non'); },
  };
  assert.equal(ecrire(refus, DEFAUT), false);
  assert.doesNotThrow(() => oublier(refus));
  assert.doesNotThrow(() => lire(refus, TOUS));
});

test('oublier ramène au défaut', () => {
  const s = stockage();
  ecrire(s, deplacer(reconcilier(null, TOUS), 'atelier', 'pilotage', 0));
  oublier(s);
  assert.deepEqual(lire(s, TOUS).onglets, DEFAUT.onglets);
});

test('la clé est versionnée, et la v1 ne se relit pas comme une v2', () => {
  // Changer la FORME sans changer la clé ferait relire un ancien rangement comme
  // un nouveau. Ici les deux garde-fous jouent : la clé a changé, ET `formeValide`
  // rejette la forme v1 si elle se présentait quand même.
  assert.match(CLE, /-v2$/);
  const v1 = { colonnes: [['atelier', 'recolte'], ['carnet']], replies: [] };
  assert.deepEqual(reconcilier(v1, TOUS).onglets, DEFAUT.onglets);
});
