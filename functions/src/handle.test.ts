import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateHandle } from './handle.js';

test('generateHandle produces an UPPER-UPPER-NN synthwave handle', () => {
  const handle = generateHandle();
  assert.match(handle, /^[A-Z]+-[A-Z]+-\d{2}$/);
});

test('generateHandle never emits a Rockstar/GTA trademark token', () => {
  const forbidden = /GTA|ROCKSTAR|VICE CITY|LEONIDA/i;
  for (let i = 0; i < 50; i++) {
    assert.doesNotMatch(generateHandle(), forbidden);
  }
});

test('generateHandle produces variety across repeated calls', () => {
  const samples = new Set(Array.from({ length: 20 }, () => generateHandle()));
  assert.ok(samples.size > 1, 'expected more than one distinct handle across 20 calls');
});
