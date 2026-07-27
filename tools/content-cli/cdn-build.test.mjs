import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSite, chunked, CHUNK_SIZE } from './cdn-build.mjs';

const KINDS = {
  poi: { collection: 'poi' },
  'poi-gtav': { collection: 'poi_gtav' },
  cheats: { collection: 'cheats' },
};

const entry = (kind, id, status = 'published') => ({ kind, data: { id, status } });

test('le manifeste porte la version, le commit et la carte des fragments', () => {
  const files = buildSite([entry('poi', 'p1')], KINDS, { version: 12, commit: 'abc1234' });
  const manifest = files.find((f) => f.path === 'content/manifest.json');

  assert.ok(manifest);
  assert.equal(manifest.json.version, 12);
  assert.equal(manifest.json.commit, 'abc1234');
  assert.equal(manifest.json.collections.poi.count, 1);
  assert.equal(manifest.json.collections.poi.chunks, 1);
});

test('chaque collection sort en fragments numérotés', () => {
  const files = buildSite([entry('poi', 'p1'), entry('cheats', 'c1')], KINDS, { version: 1, commit: 'x' });
  const paths = files.map((f) => f.path).sort();

  assert.ok(paths.includes('content/v1/poi/0.json'));
  assert.ok(paths.includes('content/v1/cheats/0.json'));
  assert.ok(paths.includes('content/v1/poi_gtav/0.json'));
});

test('un fragment a exactement la forme que le client décode', () => {
  const files = buildSite([entry('poi', 'p1')], KINDS, { version: 1, commit: 'x' });
  const bundle = files.find((f) => f.path === 'content/v1/poi/0.json');

  assert.deepEqual(Object.keys(bundle.json).sort(), ['chunk', 'collection', 'items']);
  assert.equal(bundle.json.collection, 'poi');
  assert.equal(bundle.json.chunk, 0);
  assert.equal(bundle.json.items[0].id, 'p1');
});

test('un brouillon ne part jamais vers le CDN', () => {
  const files = buildSite(
    [entry('poi', 'p1', 'draft'), entry('poi', 'p2', 'published')],
    KINDS,
    { version: 1, commit: 'x' }
  );
  const bundle = files.find((f) => f.path === 'content/v1/poi/0.json');

  assert.equal(bundle.json.items.length, 1);
  assert.equal(bundle.json.items[0].id, 'p2');
});

test('une collection vide produit un fragment vide, pas aucun fragment', () => {
  // Sinon le dernier fragment d'une collection qui se vide resterait servi.
  const files = buildSite([], KINDS, { version: 1, commit: 'x' });
  const bundle = files.find((f) => f.path === 'content/v1/cheats/0.json');

  assert.ok(bundle);
  assert.deepEqual(bundle.json.items, []);
});

test('le découpage respecte la taille de fragment', () => {
  const entries = Array.from({ length: 1200 }, (_, i) => entry('poi', `p${i}`));
  const files = buildSite(entries, KINDS, { version: 1, commit: 'x' });
  const poiChunks = files.filter((f) => f.path.startsWith('content/v1/poi/'));

  assert.equal(poiChunks.length, 3);
  const manifest = files.find((f) => f.path === 'content/manifest.json');
  assert.equal(manifest.json.collections.poi.chunks, 3);
  assert.equal(manifest.json.collections.poi.count, 1200);
});

test("le chemin des fragments porte la version, donc ils sont immuables", () => {
  // C'est ce qui autorise un cache d'un an en périphérie : une URL donnée ne
  // change jamais de contenu. Sans ça il faudrait court-cacher chaque fragment,
  // et le CDN ne servirait presque plus à rien.
  const v1 = buildSite([entry('poi', 'p1')], KINDS, { version: 1, commit: 'x' });
  const v2 = buildSite([entry('poi', 'p1')], KINDS, { version: 2, commit: 'y' });

  assert.ok(v1.some((f) => f.path === 'content/v1/poi/0.json'));
  assert.ok(v2.some((f) => f.path === 'content/v2/poi/0.json'));
  assert.ok(v1.filter((f) => f.path !== 'content/manifest.json').every((f) => f.immutable));
  assert.equal(v1.find((f) => f.path === 'content/manifest.json').immutable, false);
});

test('la taille de fragment reste alignée sur le client et Firestore', () => {
  assert.equal(CHUNK_SIZE, 500);
  assert.equal(chunked(Array.from({ length: 500 }, (_, i) => i)).length, 1);
  assert.equal(chunked(Array.from({ length: 501 }, (_, i) => i)).length, 2);
});
