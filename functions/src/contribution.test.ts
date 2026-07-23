import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateSubmission, containsBannedVocabulary, isTooCloseToExistingSpot, DEDUP_THRESHOLD_NORMALIZED } from './contribution.js';

const valid = { category: 'landmark', title: 'Great view here', position: { x: 0.5, y: 0.5 }, languageCode: 'en' };

test('validateSubmission accepts a well-formed submission', () => {
  const result = validateSubmission(valid);
  assert.equal(result.category, 'landmark');
  assert.equal(result.title, 'Great view here');
});

test('validateSubmission trims whitespace from title', () => {
  const result = validateSubmission({ ...valid, title: '  padded  ' });
  assert.equal(result.title, 'padded');
});

test('validateSubmission rejects an unknown category', () => {
  assert.throws(() => validateSubmission({ ...valid, category: 'rockstar-hq' }), /category/);
});

test('validateSubmission rejects an empty title', () => {
  assert.throws(() => validateSubmission({ ...valid, title: '   ' }), /title/);
});

test('validateSubmission rejects a title over 280 characters', () => {
  assert.throws(() => validateSubmission({ ...valid, title: 'x'.repeat(281) }), /title/);
});

test('validateSubmission rejects an out-of-range position', () => {
  assert.throws(() => validateSubmission({ ...valid, position: { x: 1.5, y: 0.5 } }), /position/);
});

test('validateSubmission rejects an unsupported language code', () => {
  assert.throws(() => validateSubmission({ ...valid, languageCode: 'ja' }), /languageCode/);
});

test('containsBannedVocabulary flags an obvious banned token', () => {
  assert.equal(containsBannedVocabulary('this spot is shit'), true);
});

test('containsBannedVocabulary flags a raw URL (spam vector)', () => {
  assert.equal(containsBannedVocabulary('check out https://example.com'), true);
});

test('containsBannedVocabulary allows clean text', () => {
  assert.equal(containsBannedVocabulary('Great rooftop view at sunset'), false);
});

test('isTooCloseToExistingSpot rejects a near-duplicate position', () => {
  const existing = [{ x: 0.5, y: 0.5 }];
  assert.equal(isTooCloseToExistingSpot({ x: 0.505, y: 0.505 }, existing), true);
});

test('isTooCloseToExistingSpot allows a position outside the threshold', () => {
  const existing = [{ x: 0.5, y: 0.5 }];
  assert.equal(isTooCloseToExistingSpot({ x: 0.9, y: 0.9 }, existing), false);
});

test('isTooCloseToExistingSpot allows any position when nothing exists yet', () => {
  assert.equal(isTooCloseToExistingSpot({ x: 0.5, y: 0.5 }, []), false);
});

test('DEDUP_THRESHOLD_NORMALIZED is the documented 0.02', () => {
  assert.equal(DEDUP_THRESHOLD_NORMALIZED, 0.02);
});
