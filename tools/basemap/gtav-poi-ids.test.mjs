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

// Mêmes champs que ceux qu'émet gtav-poi.mjs, `status: 'draft'` compris : c'est
// le pipeline qui pose ce défaut, pas reconcileIds.
const poi = (collection, processedFrom, en = 'x') => ({
  collection,
  processedFrom,
  title: { en },
  status: 'draft',
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

  const registry = new Map(first.pois.map((p) => [p.processedFrom, p]));
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
  const registry = new Map(reconcileIds(existingEntries, new Map()).pois.map((p) => [p.processedFrom, p]));

  // C'est le scénario qui cassait tout avec des ids indexés sur le rang.
  const withInsertion = [
    poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(5, 5))),
    ...existingEntries,
  ];
  const run = reconcileIds(withInsertion, registry);

  assert.equal(run.minted, 1);
  assert.equal(run.reused, 2);
  for (const [key, doc] of registry) {
    assert.equal(run.pois.find((p) => p.processedFrom === key).id, doc.id);
  }
});

test('une clé disparue devient orpheline sans que son id soit recyclé', () => {
  const before = [
    poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(10, 10))),
    poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(20, 20))),
  ];
  const registry = new Map(reconcileIds(before, new Map()).pois.map((p) => [p.processedFrom, p]));

  const after = reconcileIds([before[0]], registry);
  assert.equal(after.orphaned.length, 1);
  assert.equal(after.orphaned[0].key, before[1].processedFrom);
  assert.equal(after.pois.length, 1);
  assert.equal(after.pois[0].id, registry.get(before[0].processedFrom).id);
});

test('un ré-import préserve les décisions humaines déjà prises', () => {
  // Sans ça, relancer le pipeline remettrait les 537 POI en `draft` et
  // effacerait toutes les pierres tombales — silencieusement.
  const entry = poi('letter_scrap', identityKey('danharper/GTAV', 'letter_scrap', '412'));
  const first = reconcileIds([entry], new Map());
  const reviewed = { ...first.pois[0], status: 'published', mergedInto: 'poi_autre', deleted: false };
  const registry = new Map([[reviewed.processedFrom, reviewed]]);

  const second = reconcileIds([entry], registry);
  assert.equal(second.pois[0].status, 'published');
  assert.equal(second.pois[0].mergedInto, 'poi_autre');
  assert.equal(second.pois[0].deleted, false);
  assert.equal(second.pois[0].id, reviewed.id);
});

test('un ré-import préserve les traductions déjà écrites', () => {
  // Sans ça, relancer le pipeline rendrait muettes toutes les traductions FR
  // d'un coup, sans rien signaler : l'app replierait juste sur l'anglais.
  const entry = {
    ...poi('letter_scrap', identityKey('danharper/GTAV', 'letter_scrap', '412'), 'Letter Scrap #19'),
    note: { en: 'At the far end of the beach.' },
  };
  const translated = {
    ...reconcileIds([entry], new Map()).pois[0],
    title: { en: 'Letter Scrap #19', fr: 'Fragment de lettre #19' },
    note: { en: 'At the far end of the beach.', fr: "Le fragment est à l'extrémité de la plage." },
  };

  const second = reconcileIds([entry], new Map([[translated.processedFrom, translated]]));
  assert.equal(second.pois[0].title.fr, 'Fragment de lettre #19');
  assert.equal(second.pois[0].note.fr, "Le fragment est à l'extrémité de la plage.");
});

test('un libellé amont retouché abandonne sa traduction périmée', () => {
  // Reporter un FR qui ne dit plus la même chose que l'EN est pire que le
  // champ manquant : le manque, lui, ressort dans `translate --dry-run`.
  const key = identityKey('danharper/GTAV', 'letter_scrap', '412');
  const translated = {
    ...reconcileIds([poi('letter_scrap', key, 'Letter Scrap #19')], new Map()).pois[0],
    title: { en: 'Letter Scrap #19', fr: 'Fragment de lettre #19' },
  };

  const renamed = poi('letter_scrap', key, 'Letter Scrap #19 - Pacific Ocean');
  const second = reconcileIds([renamed], new Map([[translated.processedFrom, translated]]));
  assert.equal(second.pois[0].title.en, 'Letter Scrap #19 - Pacific Ocean');
  assert.equal(second.pois[0].title.fr, undefined);
});

test('le pipeline reste autorité sur le FR qu’il dérive lui-même', () => {
  // Le `fr` des titres vient de la table TYPES : la corriger doit se propager
  // au ré-import, sinon la table devient décorative.
  const key = identityKey('DurtyFree', 'gas', worldDiscriminant(10, 10));
  const stale = {
    ...reconcileIds([poi('gas', key, 'Gas Station')], new Map()).pois[0],
    title: { en: 'Gas Station', fr: 'Poste à essence' },
  };

  const fresh = { ...poi('gas', key, 'Gas Station'), title: { en: 'Gas Station', fr: 'Station-service' } };
  const second = reconcileIds([fresh], new Map([[stale.processedFrom, stale]]));
  assert.equal(second.pois[0].title.fr, 'Station-service');
});

test('un POI neuf n’hérite d’aucun champ éditorial', () => {
  // Une entrée fraîchement importée doit demander une décision explicite : le
  // pipeline ne publie rien de lui-même.
  const run = reconcileIds([poi('gas', identityKey('DurtyFree', 'gas', worldDiscriminant(1, 1)))], new Map());
  assert.equal(run.pois[0].status, 'draft');
  assert.equal(run.pois[0].mergedInto, undefined);
  assert.equal(run.pois[0].deleted, undefined);
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
