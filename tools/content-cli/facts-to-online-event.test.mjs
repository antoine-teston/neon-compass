import { test } from 'node:test';
import assert from 'node:assert/strict';
import { factToOnlineEvent } from './facts-to-online-event.mjs';
import { identityKey } from '../basemap/gtav-poi-ids.mjs';
import { INBOX_SOURCE, factDiscriminant } from './facts-to-news.mjs';

// Forme RÉELLE d'un fait d'inbox (.claude/agents/data-scout.md « Sortie ») :
// `source_url` est une chaîne, pas un tableau `sources` — et un événement en
// ligne porte en plus `starts_at`/`ends_at`, exigés pour ce seul kind.
const FACT = {
  kind: 'online-event',
  claim: 'Double GTA$ on sea races until August 13.',
  source_url: 'https://gtaboom.com/weekly-update',
  source_date: '2026-08-06',
  confidence: 'multi-source',
  game: 'gtav',
  starts_at: '2026-08-06T09:00:00Z',
  ends_at: '2026-08-13T09:00:00Z',
};

function expectedKey(fact) {
  return identityKey(INBOX_SOURCE, 'online-events', factDiscriminant(fact));
}

test('un squelette est produit, marqué à rédiger', () => {
  const event = factToOnlineEvent(FACT);
  assert.equal(event.status, 'draft');
  assert.equal(event.needsRewrite, true);
  assert.equal(event.game, 'gtav');
  assert.equal(event.endsAt, '2026-08-13T09:00:00Z');
});

test("l'identité est stable pour un même fait", () => {
  assert.equal(expectedKey(FACT), expectedKey({ ...FACT }));
  assert.equal(factToOnlineEvent(FACT).processedFrom, expectedKey(FACT));
});

test("l'identité change si le fait change", () => {
  assert.notEqual(expectedKey(FACT), expectedKey({ ...FACT, claim: 'autre chose' }));
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

test('un fait sans fenêtre est refusé — sans ends_at il n’y a pas de compte à rebours', () => {
  const { ends_at, ...sansFin } = FACT;
  assert.throws(() => factToOnlineEvent(sansFin), /ends_at/);
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

// La confusion entre les deux fonctions `identityKey` (l'une lisible, l'autre
// un condensat) était le défaut n°1 : ce test verrouille la forme lisible que
// tous les autres `processedFrom` du dépôt partagent.
test('processedFrom a la forme lisible « inbox:online-events:… », pas un condensat nu', () => {
  const event = factToOnlineEvent(FACT);
  assert.match(event.processedFrom, /^inbox:online-events:[a-f0-9]+$/);
});
