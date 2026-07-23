// functions/src/xp.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { levelForXP, LEVEL_THRESHOLDS, GRADE_NAMES } from './xp.js';

test('levelForXP is 0 below the first threshold', () => {
  assert.equal(levelForXP(0), 0);
  assert.equal(levelForXP(49), 0);
});

test('levelForXP steps up exactly at each threshold', () => {
  for (let i = 0; i < LEVEL_THRESHOLDS.length; i++) {
    assert.equal(levelForXP(LEVEL_THRESHOLDS[i]), i);
  }
});

test('levelForXP caps at the highest defined level for very large XP', () => {
  assert.equal(levelForXP(1_000_000), LEVEL_THRESHOLDS.length - 1);
});

test('LEVEL_THRESHOLDS and GRADE_NAMES stay in sync', () => {
  assert.equal(LEVEL_THRESHOLDS.length, GRADE_NAMES.length);
});

test('no grade name is a GTA/Rockstar trademark token', () => {
  const forbidden = /GTA|ROCKSTAR|VICE CITY|LEONIDA/i;
  for (const name of GRADE_NAMES) {
    assert.doesNotMatch(name, forbidden);
  }
});
