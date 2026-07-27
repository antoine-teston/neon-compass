import { test } from 'node:test';
import assert from 'node:assert/strict';
import { materialize, EDITOR_SOURCE } from './draft-to-poi.mjs';

const CAPTURED_ON = '2026-11-20';

function createDraft(overrides = {}) {
  return {
    id: 'uuid-1',
    kind: 'create',
    category: 'collectible',
    position: { x: 0.25, y: 0.5 },
    title: null,
    targetPOIID: null,
    sourceContributionID: null,
    ...overrides,
  };
}

function existingPOI(overrides = {}) {
  return {
    path: 'content/poi/poi_a.json',
    data: {
      id: 'poi_a',
      category: 'landmark',
      position: { x: 0.1, y: 0.1 },
      title: { en: 'A' },
      status: 'draft',
      sources: ['s'],
      ...overrides,
    },
  };
}

test('un create frappe un id stable et écrit un fichier draft', () => {
  const result = materialize([createDraft()], [], { capturedOn: CAPTURED_ON });

  assert.equal(result.writes.length, 1);
  assert.equal(result.conflicts.length, 0);
  assert.deepEqual(result.applied, ['uuid-1']);

  const { data } = result.writes[0];
  assert.match(data.id, /^poi_leonida_collectible_[0-9a-f]{8}$/);
  assert.equal(data.status, 'draft');
  assert.deepEqual(data.position, { x: 0.25, y: 0.5 });
  assert.equal(data.processedFrom, `${EDITOR_SOURCE}:collectible:uuid-1`);
  assert.ok(data.sources.length >= 1);
  assert.ok(data.title.en.length > 0);
});

test('le même brouillon rejoué ne réécrit rien mais reste appliqué', () => {
  const first = materialize([createDraft()], [], { capturedOn: CAPTURED_ON });
  const existing = [{ path: 'content/poi/x.json', data: first.writes[0].data }];

  const second = materialize([createDraft()], existing, { capturedOn: CAPTURED_ON });

  assert.equal(second.writes.length, 0);
  assert.deepEqual(second.applied, ['uuid-1']);
});

test('un titre capturé remplace le titre généré', () => {
  const result = materialize([createDraft({ title: 'Lettre sur le toit' })], [], { capturedOn: CAPTURED_ON });
  assert.equal(result.writes[0].data.title.en, 'Lettre sur le toit');
});

test('une adoption cite la contribution d’origine dans sources', () => {
  const result = materialize([createDraft({ sourceContributionID: 'c42' })], [], { capturedOn: CAPTURED_ON });
  assert.ok(result.writes[0].data.sources.some((s) => s.includes('c42')));
});

test('un move réécrit la position du POI visé sans toucher au reste', () => {
  const result = materialize(
    [{ id: 'uuid-2', kind: 'move', targetPOIID: 'poi_a', position: { x: 0.8, y: 0.9 } }],
    [existingPOI()],
    { capturedOn: CAPTURED_ON }
  );

  assert.equal(result.writes.length, 1);
  assert.equal(result.writes[0].path, 'content/poi/poi_a.json');
  assert.deepEqual(result.writes[0].data.position, { x: 0.8, y: 0.9 });
  assert.deepEqual(result.writes[0].data.title, { en: 'A' });
  assert.equal(result.writes[0].data.status, 'draft');
});

test('un move vers un POI absent est signalé, jamais appliqué à moitié', () => {
  const result = materialize(
    [{ id: 'uuid-3', kind: 'move', targetPOIID: 'poi_absent', position: { x: 0.5, y: 0.5 } }],
    [],
    { capturedOn: CAPTURED_ON }
  );

  assert.equal(result.writes.length, 0);
  assert.equal(result.skipped.length, 1);
  assert.deepEqual(result.applied, ['uuid-3']);
});

test('supprimer un POI publié écrit une pierre tombale, jamais une suppression', () => {
  const result = materialize(
    [{ id: 'uuid-4', kind: 'delete', targetPOIID: 'poi_a' }],
    [existingPOI({ status: 'published' })],
    { capturedOn: CAPTURED_ON }
  );

  assert.equal(result.deletes.length, 0);
  assert.equal(result.writes.length, 1);
  assert.equal(result.writes[0].data.deleted, true);
});

test('supprimer un POI jamais publié supprime le fichier', () => {
  const result = materialize(
    [{ id: 'uuid-5', kind: 'delete', targetPOIID: 'poi_a' }],
    [existingPOI()],
    { capturedOn: CAPTURED_ON }
  );

  assert.deepEqual(result.deletes, ['content/poi/poi_a.json']);
  assert.equal(result.writes.length, 0);
});

test('un id frappé qui collisionne avec un autre processedFrom bloque tout le lot', () => {
  const minted = materialize([createDraft()], [], { capturedOn: CAPTURED_ON }).writes[0].data;
  const existing = [{
    path: 'content/poi/collision.json',
    data: { ...minted, processedFrom: 'autre:source:autre-uuid' },
  }];

  // Un second brouillon parfaitement valide accompagne le fautif : il ne doit
  // PAS être appliqué non plus. Un lot à moitié appliqué laisserait le dépôt
  // dans un état que personne ne peut raisonner.
  const result = materialize(
    [createDraft(), createDraft({ id: 'uuid-9', category: 'vehicle' })],
    existing,
    { capturedOn: CAPTURED_ON }
  );

  assert.equal(result.conflicts.length, 1);
  assert.equal(result.writes.length, 0);
  assert.equal(result.applied.length, 0);
});

test('deux brouillons distincts produisent deux ids distincts', () => {
  const result = materialize(
    [createDraft(), createDraft({ id: 'uuid-2' })],
    [],
    { capturedOn: CAPTURED_ON }
  );

  assert.equal(result.writes.length, 2);
  assert.notEqual(result.writes[0].data.id, result.writes[1].data.id);
});

test('deux créations de même catégorie dans le même lot ne se marchent pas dessus', () => {
  // Régression possible : si l'index des ids n'est pas tenu à jour au fil du
  // lot, une collision entre deux entrées du MÊME run passerait inaperçue.
  const result = materialize(
    [createDraft(), createDraft()],
    [],
    { capturedOn: CAPTURED_ON }
  );

  // Même uuid deux fois : la seconde se réapparie à la première, elle n'écrit pas
  // un second fichier portant le même id.
  assert.equal(result.writes.length, 1);
  assert.equal(result.conflicts.length, 0);
});
