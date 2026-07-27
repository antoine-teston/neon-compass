// node --test tools/basemap/gtav-poi-ids.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  dedupeIdenticalEntries,
  formatWorldCoord,
  worldDiscriminant,
  hasDuplicateUpstreamIds,
  identityKey,
  mintId,
  reconcileIds,
} from './gtav-poi-ids.mjs';

const poi = (collection, processedFrom, en = 'x') => ({
  collection,
  processedFrom,
  title: { en },
});

test('formatWorldCoord arrondit au décimètre sans produire de -0.0', () => {
  assert.equal(formatWorldCoord(-1150.24), '-1150.2');
  assert.equal(formatWorldCoord(-1150.26), '-1150.3');
  // Un -0.0 rendrait la clé dépendante du signe d'un flottant quasi nul : deux
  // runs sur la même donnée doivent produire exactement la même chaîne.
  assert.equal(formatWorldCoord(-0.01), '0.0');
  assert.equal(formatWorldCoord(0), '0.0');
});

test('worldDiscriminant est stable pour deux flottants qui arrondissent pareil', () => {
  assert.equal(worldDiscriminant(-1150.23, -1518.44), worldDiscriminant(-1150.246, -1518.435));
});

test('hasDuplicateUpstreamIds repère la réutilisation d’un id amont', () => {
  assert.equal(hasDuplicateUpstreamIds([1, 2, 3]), false);
  assert.equal(hasDuplicateUpstreamIds([1, 2, 2]), true);
  // Les sources mélangent nombres et chaînes ; « 2 » et 2 sont le même id.
  assert.equal(hasDuplicateUpstreamIds([2, '2']), true);
  assert.equal(hasDuplicateUpstreamIds([]), false);
});

test('mintId produit un id conforme au schéma et déterministe', () => {
  const key = identityKey('danharper/GTAV', 'letter_scrap', '412');
  const id = mintId('gtav', 'letter_scrap', key);
  assert.match(id, /^poi_[a-z0-9_]+$/);
  assert.equal(id, mintId('gtav', 'letter_scrap', key));
  assert.notEqual(id, mintId('gtav', 'letter_scrap', identityKey('gta5-map', 'letter_scrap', '412')));
});

test('un second run consécutif ne frappe aucun id', () => {
  const entries = [
    poi('letter_scrap', identityKey('danharper/GTAV', 'letter_scrap', '412')),
    poi('garage', identityKey('DurtyFree', 'garage', worldDiscriminant(-1150.2, -1518.4))),
  ];

  const first = reconcileIds(entries, new Map());
  assert.equal(first.minted, 2);
  assert.equal(first.reused, 0);

  const registry = new Map(first.pois.map((p) => [p.processedFrom, p.id]));
  const second = reconcileIds(entries, registry);
  assert.equal(second.minted, 0);
  assert.equal(second.reused, 2);
  assert.deepEqual(
    second.pois.map((p) => p.id),
    first.pois.map((p) => p.id),
  );
});

test('un POI inséré en tête ne déplace pas les ids existants', () => {
  const existingEntries = [
    poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(10, 10))),
    poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(20, 20))),
  ];
  const registry = new Map(reconcileIds(existingEntries, new Map()).pois.map((p) => [p.processedFrom, p.id]));

  // C'est le scénario qui cassait tout avec des ids indexés sur le rang.
  const withInsertion = [
    poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(5, 5))),
    ...existingEntries,
  ];
  const run = reconcileIds(withInsertion, registry);

  assert.equal(run.minted, 1);
  assert.equal(run.reused, 2);
  for (const [key, id] of registry) {
    assert.equal(run.pois.find((p) => p.processedFrom === key).id, id);
  }
});

test('une clé disparue devient orpheline sans que son id soit recyclé', () => {
  const before = [
    poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(10, 10))),
    poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(20, 20))),
  ];
  const registry = new Map(reconcileIds(before, new Map()).pois.map((p) => [p.processedFrom, p.id]));

  const after = reconcileIds([before[0]], registry);
  assert.equal(after.orphaned.length, 1);
  assert.equal(after.orphaned[0].key, before[1].processedFrom);
  assert.equal(after.pois.length, 1);
  assert.equal(after.pois[0].id, registry.get(before[0].processedFrom));
});

test('une entrée listée deux fois à l’identique n’est gardée qu’une fois', () => {
  // Le cas réel : garages.json liste chacun de ses 16 garages en double.
  const key = identityKey('DurtyFree', 'garage', `Michael@${worldDiscriminant(-814.4, 183.3)}`);
  const { pois: kept, dropped } = dedupeIdenticalEntries([poi('garage', key), poi('garage', key)]);
  assert.equal(kept.length, 1);
  assert.equal(dropped, 1);
});

test('même clé mais contenu différent n’est pas dédupliqué', () => {
  // Ce n'est pas un doublon amont mais un discriminant trop grossier : il faut
  // que reconcileIds lève, pas qu'on perde silencieusement un POI distinct.
  const key = identityKey('DurtyFree', 'garage', 'X=0.0,Y=0.0');
  const { pois: kept, dropped } = dedupeIdenticalEntries([poi('garage', key, 'A'), poi('garage', key, 'B')]);
  assert.equal(kept.length, 2);
  assert.equal(dropped, 0);
  assert.throws(() => reconcileIds(kept, new Map()), /clé d'identité dupliquée/);
});

test('deux POI de même clé arrêtent le run au lieu d’être suffixés', () => {
  const key = identityKey('gta5-map', 'wall_breach', '26');
  assert.throws(
    () => reconcileIds([poi('wall_breach', key, 'Dollar Pills'), poi('wall_breach', key, "Floyd's house")], new Map()),
    /clé d'identité dupliquée/,
  );
});

test('un discriminant à coordonnées sépare deux entrées de même id amont', () => {
  const a = identityKey('gta5-map', 'wall_breach', `26@${worldDiscriminant(1, 1)}`);
  const b = identityKey('gta5-map', 'wall_breach', `26@${worldDiscriminant(2, 2)}`);
  const run = reconcileIds([poi('wall_breach', a), poi('wall_breach', b)], new Map());
  assert.equal(run.minted, 2);
  assert.notEqual(run.pois[0].id, run.pois[1].id);
});
