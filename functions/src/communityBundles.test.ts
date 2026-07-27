import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  isDirtyingChange,
  shouldRebuild,
  isPubliclyVisible,
  bundleItem,
  chunked,
  CHUNK_SIZE,
  FORCED_REBUILD_INTERVAL_MS,
} from './communityBundles.js';

const spot = (overrides: Record<string, unknown> = {}) => ({
  authorUid: 'u1',
  authorHandle: 'NEON-FALCON-88',
  category: 'collectible',
  title: 'Lettre sur le toit',
  languageCode: 'fr',
  position: { x: 0.25, y: 0.5 },
  status: 'approved',
  upvotes: 3,
  downvotes: 0,
  ...overrides,
});

test('un vote ne salit pas les fragments', () => {
  // Le cœur du dispositif : sans ça, le pic de votes reconstruirait en continu.
  assert.equal(isDirtyingChange(spot(), spot({ upvotes: 4 })), false);
  assert.equal(isDirtyingChange(spot(), spot({ upvotes: 9, downvotes: 2 })), false);
});

test('une approbation salit les fragments', () => {
  assert.equal(isDirtyingChange(spot({ status: 'pending' }), spot({ status: 'approved' })), true);
});

test('un shadow-ban salit les fragments', () => {
  assert.equal(isDirtyingChange(spot(), spot({ shadowHidden: true })), true);
});

test('un déplacement ou un retitrage salit les fragments', () => {
  assert.equal(isDirtyingChange(spot(), spot({ position: { x: 0.9, y: 0.1 } })), true);
  assert.equal(isDirtyingChange(spot(), spot({ title: 'Autre titre' })), true);
});

test('création et suppression salissent toujours', () => {
  assert.equal(isDirtyingChange(undefined, spot()), true);
  assert.equal(isDirtyingChange(spot(), undefined), true);
});

test('reconstruit si sale, si jamais construit, ou si trop vieux', () => {
  const now = 1_800_000_000_000;
  assert.equal(shouldRebuild(undefined, now), true);
  assert.equal(shouldRebuild({ dirty: true, builtAtMs: now }, now), true);
  assert.equal(shouldRebuild({ dirty: false, builtAtMs: now }, now), false);
  assert.equal(shouldRebuild({ dirty: false, builtAtMs: now - 60_000 }, now), false);
  assert.equal(
    shouldRebuild({ dirty: false, builtAtMs: now - FORCED_REBUILD_INTERVAL_MS }, now),
    true,
    'le rafraîchissement horaire est ce qui dégèle les compteurs de votes'
  );
});

test('seuls les spots approuvés et non masqués partent en fragment', () => {
  assert.equal(isPubliclyVisible(spot()), true);
  assert.equal(isPubliclyVisible(spot({ status: 'pending' })), false);
  assert.equal(isPubliclyVisible(spot({ status: 'rejected' })), false);
  // Le client ne lit plus `contributions`, donc la Security Rule ne filtre plus
  // rien ici : ce test est le seul garde-fou du shadow-ban sur ce chemin.
  assert.equal(isPubliclyVisible(spot({ shadowHidden: true })), false);
});

test('la projection ne laisse pas fuir de champ serveur', () => {
  const item = bundleItem('c1', spot({ flaggedForReview: true, createdAt: 'un timestamp' }));
  assert.deepEqual(Object.keys(item).sort(), [
    'authorHandle', 'authorUid', 'category', 'downvotes', 'id',
    'languageCode', 'position', 'status', 'title', 'upvotes',
  ]);
  assert.equal(item.id, 'c1');
});

test('un auteur anonyme sort en null, pas en undefined', () => {
  // undefined ferait échouer l'écriture Firestore ; null est décodable côté
  // Swift comme `authorUid: String?`.
  assert.equal(bundleItem('c1', spot({ authorUid: undefined })).authorUid, null);
});

test('le découpage respecte la taille de fragment', () => {
  const items = Array.from({ length: 1200 }, (_, i) => i);
  const chunks = chunked(items);
  assert.equal(chunks.length, 3);
  assert.equal(chunks[0].length, CHUNK_SIZE);
  assert.equal(chunks[2].length, 200);
});

test('une collection vide produit un fragment vide, pas aucun fragment', () => {
  // Sinon le dernier fragment d'une collection qui se vide resterait en ligne.
  const chunks = chunked([]);
  assert.equal(chunks.length, 1);
  assert.deepEqual(chunks[0], []);
});

test('la taille de fragment reste alignée sur le client et le CLI', () => {
  assert.equal(CHUNK_SIZE, 500);
});
