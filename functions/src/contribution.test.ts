import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateSubmission } from './contribution.js';

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
