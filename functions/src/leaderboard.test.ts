import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { tallyApproved, rankContributors } from './leaderboard.js';

const c = (authorUid: string, extra = {}) => ({ authorUid, authorHandle: `H-${authorUid}`, ...extra });

describe('tallyApproved', () => {
  it('compte les contributions par auteur', () => {
    const tally = tallyApproved([c('u1'), c('u1'), c('u2')]);
    assert.equal(tally.get('u1')?.approvedCount, 2);
    assert.equal(tally.get('u2')?.approvedCount, 1);
  });

  it('écarte les contributions masquées', () => {
    const tally = tallyApproved([c('u1'), c('u1', { shadowHidden: true })]);
    assert.equal(tally.get('u1')?.approvedCount, 1);
  });

  it('fait disparaître un auteur entièrement masqué', () => {
    const tally = tallyApproved([c('u1', { shadowHidden: true })]);
    assert.equal(tally.has('u1'), false);
  });

  it('retient le handle dénormalisé de la contribution', () => {
    const tally = tallyApproved([c('u1')]);
    assert.equal(tally.get('u1')?.handle, 'H-u1');
  });
});

describe('rankContributors', () => {
  const tally = tallyApproved([c('u1'), c('u2'), c('u2'), c('u3')]);

  it("classe par XP décroissante, pas par nombre de contributions", () => {
    const xp = new Map([['u1', 300], ['u2', 100], ['u3', 200]]);
    assert.deepEqual(rankContributors(tally, xp, 50).map((r) => r.uid), ['u1', 'u3', 'u2']);
  });

  it("traite une XP absente comme zéro plutôt que d'écarter l'auteur", () => {
    const xp = new Map([['u1', 10]]);
    const rows = rankContributors(tally, xp, 50);
    assert.equal(rows.length, 3);
    assert.equal(rows.find((r) => r.uid === 'u2')?.xp, 0);
  });

  it('départage à XP égale par identifiant, pour un ordre déterministe', () => {
    const t = tallyApproved([c('b'), c('a')]);
    const xp = new Map([['a', 100], ['b', 100]]);
    assert.deepEqual(rankContributors(t, xp, 50).map((r) => r.uid), ['a', 'b']);
  });

  it('tronque au nombre demandé', () => {
    const many = tallyApproved(Array.from({ length: 80 }, (_, i) => c(`u${i}`)));
    assert.equal(rankContributors(many, new Map(), 50).length, 50);
  });

  it('ne publie que les quatre champs du classement', () => {
    const rows = rankContributors(tallyApproved([c('u1')]), new Map([['u1', 5]]), 50);
    assert.deepEqual(Object.keys(rows[0]).sort(), ['approvedCount', 'handle', 'uid', 'xp']);
  });
});
