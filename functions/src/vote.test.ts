import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyVoteDelta } from './vote.js';

test('first upvote', () => {
  assert.deepEqual(applyVoteDelta(null, 'up'), { upvoteDelta: 1, downvoteDelta: 0 });
});

test('first downvote', () => {
  assert.deepEqual(applyVoteDelta(null, 'down'), { upvoteDelta: 0, downvoteDelta: 1 });
});

test('re-voting the same direction is a no-op', () => {
  assert.deepEqual(applyVoteDelta('up', 'up'), { upvoteDelta: 0, downvoteDelta: 0 });
  assert.deepEqual(applyVoteDelta('down', 'down'), { upvoteDelta: 0, downvoteDelta: 0 });
});

test('switching from up to down moves one vote across buckets', () => {
  assert.deepEqual(applyVoteDelta('up', 'down'), { upvoteDelta: -1, downvoteDelta: 1 });
});

test('switching from down to up moves one vote across buckets', () => {
  assert.deepEqual(applyVoteDelta('down', 'up'), { upvoteDelta: 1, downvoteDelta: -1 });
});
