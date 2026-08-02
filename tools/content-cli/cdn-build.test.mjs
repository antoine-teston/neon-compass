import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSite, chunked, stableStringify, CHUNK_SIZE } from './cdn-build.mjs';

const KINDS = {
  poi: { collection: 'poi' },
  'poi-gtav': { collection: 'poi_gtav' },
  cheats: { collection: 'cheats' },
};

const entry = (kind, id, status = 'published') => ({ kind, data: { id, status } });

test('le manifeste porte la version, le commit et la carte des fragments', () => {
  const { files } = buildSite([entry('poi', 'p1')], KINDS, { version: 12, commit: 'abc1234' });
  const manifest = files.find((f) => f.path === 'content/manifest.json');

  assert.ok(manifest);
  assert.equal(manifest.json.version, 12);
  assert.equal(manifest.json.commit, 'abc1234');
  assert.equal(manifest.json.collections.poi.count, 1);
  assert.equal(manifest.json.collections.poi.chunks, 1);
  assert.equal(manifest.json.collections.poi.version, 12);
});

test("l'empreinte ne part pas sur le réseau", () => {
  // Elle sert à décider ici. Un client n'en fait rien, et elle voyagerait à
  // chaque session pour rien.
  const { files, collections } = buildSite([entry('poi', 'p1')], KINDS, { version: 1, commit: 'x' });
  const manifest = files.find((f) => f.path === 'content/manifest.json');

  assert.ok(collections.poi.digest, "le verrou, lui, porte bien l'empreinte");
  assert.equal(manifest.json.collections.poi.digest, undefined);
});

test('chaque collection sort en fragments numérotés', () => {
  const { files } = buildSite([entry('poi', 'p1'), entry('cheats', 'c1')], KINDS, { version: 1, commit: 'x' });
  const paths = files.map((f) => f.path).sort();

  assert.ok(paths.includes('content/v1/poi/0.json'));
  assert.ok(paths.includes('content/v1/cheats/0.json'));
  assert.ok(paths.includes('content/v1/poi_gtav/0.json'));
});

test('un fragment a exactement la forme que le client décode', () => {
  const { files } = buildSite([entry('poi', 'p1')], KINDS, { version: 1, commit: 'x' });
  const bundle = files.find((f) => f.path === 'content/v1/poi/0.json');

  assert.deepEqual(Object.keys(bundle.json).sort(), ['chunk', 'collection', 'items']);
  assert.equal(bundle.json.collection, 'poi');
  assert.equal(bundle.json.chunk, 0);
  assert.equal(bundle.json.items[0].id, 'p1');
});

test('un brouillon ne part jamais vers le CDN', () => {
  const { files } = buildSite(
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
  const { files } = buildSite([], KINDS, { version: 1, commit: 'x' });
  const bundle = files.find((f) => f.path === 'content/v1/cheats/0.json');

  assert.ok(bundle);
  assert.deepEqual(bundle.json.items, []);
});

test('le découpage respecte la taille de fragment', () => {
  const entries = Array.from({ length: 1200 }, (_, i) => entry('poi', `p${i}`));
  const { files } = buildSite(entries, KINDS, { version: 1, commit: 'x' });
  const poiChunks = files.filter((f) => f.path.startsWith('content/v1/poi/'));

  assert.equal(poiChunks.length, 3);
  const manifest = files.find((f) => f.path === 'content/manifest.json');
  assert.equal(manifest.json.collections.poi.chunks, 3);
  assert.equal(manifest.json.collections.poi.count, 1200);
});

test('le chemin des fragments porte la version, donc ils sont immuables', () => {
  // C'est ce qui autorise un cache d'un an en périphérie : une URL donnée ne
  // change jamais de contenu. Sans ça il faudrait court-cacher chaque fragment,
  // et le CDN ne servirait presque plus à rien.
  const v1 = buildSite([entry('poi', 'p1')], KINDS, { version: 1, commit: 'x' });
  const v2 = buildSite([entry('poi', 'p2')], KINDS, { version: 2, commit: 'y' });

  assert.ok(v1.files.some((f) => f.path === 'content/v1/poi/0.json'));
  assert.ok(v2.files.some((f) => f.path === 'content/v2/poi/0.json'));
  assert.ok(v1.files.filter((f) => f.path !== 'content/manifest.json').every((f) => f.immutable));
  assert.equal(v1.files.find((f) => f.path === 'content/manifest.json').immutable, false);
});

// ---------------------------------------------------------------------------
// Version par collection — le levier principal sur l'egress
// ---------------------------------------------------------------------------

test("une collection inchangée garde sa version, donc son chemin, donc le cache", () => {
  // Le défaut que ceci corrige : une publication d'actu faisait retélécharger
  // les 327 Ko de POI à tous les clients, la version étant globale.
  const first = buildSite([entry('poi', 'p1'), entry('cheats', 'c1')], KINDS, {
    version: 10,
    commit: 'a',
  });

  // Deuxième publication : seuls les cheats bougent.
  const second = buildSite([entry('poi', 'p1'), entry('cheats', 'c1'), entry('cheats', 'c2')], KINDS, {
    version: 11,
    commit: 'b',
    previous: first.collections,
  });

  assert.equal(second.collections.poi.version, 10, 'les POI ne doivent pas bouger');
  assert.equal(second.collections.cheats.version, 11, 'les cheats ont changé');
  assert.ok(second.files.some((f) => f.path === 'content/v10/poi/0.json'));
  assert.ok(second.files.some((f) => f.path === 'content/v11/cheats/0.json'));
});

test("réordonner les clés d'une entrée ne change pas la version", () => {
  // L'empreinte porte sur le contenu, pas sur la sérialisation. Sans clés
  // triées, réenregistrer un JSON ferait avancer la version — donc un
  // retéléchargement complet — sans qu'une seule valeur ait bougé.
  const a = buildSite([{ kind: 'poi', data: { id: 'p1', status: 'published', title: 'x', note: 'y' } }], KINDS, {
    version: 5,
    commit: 'a',
  });
  const b = buildSite([{ kind: 'poi', data: { note: 'y', title: 'x', status: 'published', id: 'p1' } }], KINDS, {
    version: 6,
    commit: 'b',
    previous: a.collections,
  });

  assert.equal(b.collections.poi.version, 5);
});

test('un contenu modifié sans nouveau commit avance quand même la version', () => {
  // Le piège : la version vient du nombre de commits, donc republier deux fois
  // depuis le MÊME commit avec un contenu différent donnait deux fois la même
  // version, donc le même chemin — servi `immutable` pour un an. Le nouveau
  // contenu n'atteignait jamais un client déjà passé par là.
  const first = buildSite([entry('poi', 'p1')], KINDS, { version: 345, commit: 'a' });
  const second = buildSite([entry('poi', 'p1'), entry('poi', 'p2')], KINDS, {
    version: 345,
    commit: 'a',
    previous: first.collections,
  });

  assert.equal(first.collections.poi.version, 345);
  assert.equal(second.collections.poi.version, 346, 'la version doit avancer, pas stagner');
  // `buildSite` rend des chemins logiques ; c'est `cli.js` qui ajoute le `.z`
  // en écrivant le fichier compressé.
  assert.ok(second.files.some((f) => f.path === 'content/v346/poi/0.json'));
});

test('une version ne recule jamais, même si le nombre de commits recule', () => {
  // Ceinture contre une histoire git réécrite. Une version qui recule
  // laisserait les clients sur leur cache pour toujours : la garde
  // `remoteVersion > localVersion` de ContentStore ne mordrait plus jamais.
  const first = buildSite([entry('poi', 'p1')], KINDS, { version: 100, commit: 'a' });
  const second = buildSite([entry('poi', 'p2')], KINDS, {
    version: 40,
    commit: 'b',
    previous: first.collections,
  });

  // 101 et non 100 : le contenu a changé, donc la version doit AVANCER, même
  // quand le compteur de commits, lui, a reculé.
  assert.equal(second.collections.poi.version, 101);
});

test("une collection inchangée ne bouge pas, même si le compteur de commits bondit", () => {
  // La contrepartie de la règle précédente : avancer strictement à tout
  // changement ne doit pas devenir avancer à chaque publication.
  const first = buildSite([entry('poi', 'p1')], KINDS, { version: 10, commit: 'a' });
  const second = buildSite([entry('poi', 'p1')], KINDS, {
    version: 900,
    commit: 'b',
    previous: first.collections,
  });

  assert.equal(second.collections.poi.version, 10);
});

test('sans verrou précédent, tout part à la version courante', () => {
  // Le cas de la toute première publication, et celui d'un verrou perdu : on ne
  // devine pas, on republie tout.
  const { collections } = buildSite([entry('poi', 'p1')], KINDS, { version: 7, commit: 'a' });
  assert.equal(collections.poi.version, 7);
  assert.equal(collections.cheats.version, 7);
});

test('la taille de fragment reste alignée sur le client', () => {
  assert.equal(CHUNK_SIZE, 500);
  assert.equal(chunked(Array.from({ length: 500 }, (_, i) => i)).length, 1);
  assert.equal(chunked(Array.from({ length: 501 }, (_, i) => i)).length, 2);
});

test('stableStringify trie les clés récursivement', () => {
  assert.equal(
    stableStringify({ b: 1, a: { d: 2, c: [{ f: 3, e: 4 }] } }),
    '{"a":{"c":[{"e":4,"f":3}],"d":2},"b":1}'
  );
});
