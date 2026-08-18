// node --test tools/content-cli/listed-at.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { aEstampiller } from './listed-at.mjs';

const AUJOURDHUI = '2026-08-17';

function actu(champs = {}) {
  return {
    kind: 'news',
    file: 'news/news_x.json',
    data: {
      id: 'news_x',
      category: 'announcement',
      game: 'leonida',
      title: { en: 'T' },
      body: { en: 'B' },
      publishedAt: '2026-08-10',
      status: 'published',
      sources: ['https://exemple.test/a'],
      confidence: 'single-source',
      ...champs,
    },
  };
}

test('une actu publiée sans date de mise en ligne en reçoit une', () => {
  const [{ file, data }] = aEstampiller([actu()], AUJOURDHUI);
  assert.equal(file, 'news/news_x.json');
  assert.equal(data.listedAt, AUJOURDHUI);
  // La date de l'information ne bouge pas : c'est tout l'objet du second champ.
  assert.equal(data.publishedAt, '2026-08-10');
});

test('un brouillon n’est pas estampillé', () => {
  assert.deepEqual(aEstampiller([actu({ status: 'draft' })], AUJOURDHUI), []);
});

// L'INVARIANT DU CHANTIER. Sans lui, chaque publication réestampillerait tout le
// fil à la date du jour : l'ordre d'arrivée serait perdu, et le fil se
// réordonnerait tout seul à chaque merge.
test('une actu déjà estampillée n’est jamais réestampillée', () => {
  assert.deepEqual(aEstampiller([actu({ listedAt: '2026-08-11' })], AUJOURDHUI), []);
});

test('une estampille vide ou blanche compte pour absente', () => {
  assert.equal(aEstampiller([actu({ listedAt: '' })], AUJOURDHUI).length, 1);
  assert.equal(aEstampiller([actu({ listedAt: '   ' })], AUJOURDHUI).length, 1);
});

test('les autres kinds ne sont pas touchés', () => {
  const autres = [
    { kind: 'online-events', file: 'online-events/e.json', data: { id: 'e', status: 'published' } },
    { kind: 'poi', file: 'poi/p.json', data: { id: 'p', status: 'published' } },
    { kind: 'cheats', file: 'cheats/c.json', data: { id: 'c', status: 'published' } },
  ];
  assert.deepEqual(aEstampiller(autres, AUJOURDHUI), []);
});

// L'ordre des clés n'est pas de la coquetterie : le diff d'une publication est
// relu à la main, et une clé ajoutée en fin d'objet se lit loin du champ qu'elle
// nuance.
test('la date de mise en ligne se range juste après celle de l’information', () => {
  const [{ data }] = aEstampiller([actu()], AUJOURDHUI);
  const cles = Object.keys(data);
  assert.equal(cles[cles.indexOf('publishedAt') + 1], 'listedAt');
});

test('un objet sans publishedAt reçoit quand même son estampille', () => {
  // Cas qui ne devrait pas exister — le schéma exige `publishedAt`. Mais un
  // rangement de clés qui LÈVE ferait échouer la publication entière au lieu du
  // seul fichier fautif, et c'est `validate` qui doit attraper ça, pas nous.
  const sans = { kind: 'news', file: 'news/n.json', data: { id: 'n', status: 'published' } };
  const [{ data }] = aEstampiller([sans], AUJOURDHUI);
  assert.equal(data.listedAt, AUJOURDHUI);
});

test('le lot rendu ne contient que ce qui change', () => {
  const lot = [
    actu(),
    actu({ id: 'news_y', status: 'draft' }),
    actu({ id: 'news_z', listedAt: '2026-08-01' }),
  ];
  assert.equal(aEstampiller(lot, AUJOURDHUI).length, 1);
});

test('les entrées d’origine ne sont pas mutées', () => {
  const lot = [actu()];
  aEstampiller(lot, AUJOURDHUI);
  assert.equal(lot[0].data.listedAt, undefined);
});
