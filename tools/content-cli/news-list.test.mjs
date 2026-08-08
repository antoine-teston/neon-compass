// node --test tools/content-cli/news-list.test.mjs
//
// Les filtres de date se testent sur un jour de référence PASSÉ en argument.
// Lire l'horloge dans le calcul rendrait `--days 7` invérifiable : le test
// passerait aujourd'hui et raconterait autre chose demain.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { filtrer, formater, ilYA, intervalle, jourValide, trier } from './news-list.mjs';

const AUJOURDHUI = '2026-08-08';

const ACTUS = [
  { id: 'a', date: '2026-08-08', status: 'draft', titre: 'du jour' },
  { id: 'b', date: '2026-08-05', status: 'published', titre: 'il y a trois jours' },
  { id: 'c', date: '2026-07-20', status: 'draft', titre: 'le mois dernier' },
  { id: 'd', date: null, status: null, titre: 'cassée', illisible: 'JSON tronqué' },
];

// ---------------------------------------------------------------------------
// Les bornes
// ---------------------------------------------------------------------------

test('une date mal formée est REFUSÉE, pas ignorée', () => {
  // Ignorer rendrait la liste entière et donnerait à croire qu'il n'y a rien à
  // filtrer — un faux « tout va bien » sur une faute de frappe.
  assert.throws(() => jourValide('08/2026', '--since'), /AAAA-MM-JJ/);
  assert.throws(() => jourValide('2026-8-1', '--since'), /AAAA-MM-JJ/);
  assert.throws(() => jourValide('2026-13-01', '--since'), /n'existe pas dans le calendrier/);
  assert.equal(jourValide('2026-08-08', '--since'), '2026-08-08');
});

test('--days compte AUJOURD’HUI comme premier jour', () => {
  // `--days 1` doit rendre les actus du jour. Compter à partir d'hier ferait
  // dire « aucune actu » un jour où l'on vient d'en publier trois.
  assert.deepEqual(intervalle({ days: '1' }, AUJOURDHUI), { depuis: '2026-08-08', jusqua: null });
  assert.deepEqual(intervalle({ days: '7' }, AUJOURDHUI), { depuis: '2026-08-02', jusqua: null });
});

test('ilYA traverse un changement de mois', () => {
  assert.equal(ilYA(10, '2026-08-08'), '2026-07-29');
  assert.equal(ilYA(0, '2026-08-08'), '2026-08-08');
});

test('--days et --since ensemble sont un refus', () => {
  // Ils disent la même chose. En accepter un silencieusement laisserait croire
  // que l'autre agit.
  assert.throws(() => intervalle({ days: '7', since: '2026-01-01' }, AUJOURDHUI), /n'en garder qu'un/);
});

test('un nombre de jours absurde est refusé', () => {
  for (const days of ['0', '-3', 'sept', '1.5', '99999']) {
    assert.throws(() => intervalle({ days }, AUJOURDHUI), /nombre de jours/, `accepté : ${days}`);
  }
});

test('un intervalle inversé est refusé, pas rendu vide', () => {
  // Rendre « aucune actu » sur une inversion de saisie, c'est le zéro qui se
  // prend pour un fait.
  assert.throws(
    () => intervalle({ since: '2026-08-09', until: '2026-08-01' }, AUJOURDHUI),
    /intervalle vide/,
  );
});

test('sans option, il n’y a pas de borne', () => {
  assert.deepEqual(intervalle({}, AUJOURDHUI), { depuis: null, jusqua: null });
});

// ---------------------------------------------------------------------------
// Le filtre
// ---------------------------------------------------------------------------

test('les bornes sont COMPRISES', () => {
  const r = filtrer(ACTUS, { depuis: '2026-08-05', jusqua: '2026-08-08' });
  assert.deepEqual(r.map((i) => i.id), ['a', 'b']);
});

test('une actu sans date survit tant qu’aucune borne n’est posée', () => {
  // Un fichier cassé ne doit pas disparaître au moment précis où on liste le
  // contenu pour comprendre ce qui cloche.
  assert.ok(filtrer(ACTUS, {}).some((i) => i.id === 'd'));
  assert.ok(!filtrer(ACTUS, { depuis: '2026-01-01' }).some((i) => i.id === 'd'));
});

test('le filtre de statut se combine aux dates', () => {
  const r = filtrer(ACTUS, { depuis: '2026-08-01', status: 'published' });
  assert.deepEqual(r.map((i) => i.id), ['b']);
});

test('les plus récentes d’abord, et l’ordre ne bouge pas d’une exécution à l’autre', () => {
  const memeJour = [
    { id: 'z', date: '2026-08-08' },
    { id: 'a', date: '2026-08-08' },
    { id: 'm', date: '2026-08-01' },
  ];
  assert.deepEqual(trier(memeJour).map((i) => i.id), ['a', 'z', 'm']);
});

// ---------------------------------------------------------------------------
// Le rendu
// ---------------------------------------------------------------------------

test('une liste vide dit CE QU’ON cherchait', () => {
  // « aucune actu » tout court laisse croire que le dépôt est vide.
  const texte = formater([], { depuis: '2026-08-01', status: 'published' });
  assert.match(texte, /depuis 2026-08-01/);
  assert.match(texte, /en published/);
});

test('le pied compte publiées, brouillons et cassées', () => {
  const texte = formater(ACTUS, {});
  assert.match(texte, /4 actu\(s\)/);
  assert.match(texte, /● 1 publiée\(s\)/);
  assert.match(texte, /○ 2 brouillon\(s\)/);
  assert.match(texte, /✘ 1 illisible\(s\)/);
});

test('une actu illisible est NOMMÉE, avec sa raison', () => {
  assert.match(formater(ACTUS, {}), /ILLISIBLE — JSON tronqué/);
});

test('le statut ne se lit pas à la seule couleur — il a une marque', () => {
  const texte = formater(ACTUS, {});
  assert.match(texte, /● 2026-08-05/);
  assert.match(texte, /○ 2026-08-08/);
});
