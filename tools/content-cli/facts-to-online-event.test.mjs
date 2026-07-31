import { test } from 'node:test';
import assert from 'node:assert/strict';
import { factToOnlineEvent, identityKey } from './facts-to-online-event.mjs';

const FACT = {
  kind: 'online-event',
  claim: 'Double GTA$ on sea races until August 13.',
  sources: ['https://gtaboom.com/weekly-update'],
  confidence: 'multi-source',
  game: 'gtav',
  startsAt: '2026-08-06T09:00:00Z',
  endsAt: '2026-08-13T09:00:00Z',
};

test('un squelette est produit, marqué à rédiger', () => {
  const event = factToOnlineEvent(FACT);
  assert.equal(event.status, 'draft');
  assert.equal(event.needsRewrite, true);
  assert.equal(event.game, 'gtav');
  assert.equal(event.endsAt, '2026-08-13T09:00:00Z');
});

test("l'identité est stable pour un même fait", () => {
  assert.equal(identityKey(FACT), identityKey({ ...FACT }));
  assert.equal(factToOnlineEvent(FACT).processedFrom, identityKey(FACT));
});

test("l'identité change si le fait change", () => {
  assert.notEqual(identityKey(FACT), identityKey({ ...FACT, claim: 'autre chose' }));
});

test("l'identifiant respecte le motif du schéma", () => {
  const event = factToOnlineEvent(FACT);
  assert.match(event.id, /^online_[a-z0-9_]+$/);
});

test('le fait brut est conservé pour la relecture, jamais comme titre', () => {
  const event = factToOnlineEvent(FACT);
  assert.equal(event.sourceClaim, FACT.claim);
  assert.notEqual(event.title.en, FACT.claim);
});

test('un fait sans fenêtre est refusé — sans endsAt il n’y a pas de compte à rebours', () => {
  const { endsAt, ...sansFin } = FACT;
  assert.throws(() => factToOnlineEvent(sansFin), /endsAt/);
});

/// Le schéma est en additionalProperties:false : tout champ hors contrat fait
/// échouer la validation du CLI, pas la transformation — d'où ce test ici.
test('aucun champ hors schéma n’est produit', () => {
  const permis = new Set(['id', 'game', 'startsAt', 'endsAt', 'title', 'bonuses', 'discounts',
    'podiumVehicle', 'status', 'sources', 'confidence', 'processedFrom', 'sourceClaim', 'needsRewrite']);
  for (const key of Object.keys(factToOnlineEvent(FACT))) {
    assert.ok(permis.has(key), `champ hors schéma : ${key}`);
  }
});
