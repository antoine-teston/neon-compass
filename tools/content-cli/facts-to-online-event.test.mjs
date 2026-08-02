import { test } from 'node:test';
import assert from 'node:assert/strict';
import { factToOnlineEvent, materializeOnlineEvents } from './facts-to-online-event.mjs';
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

// Parité avec `invalidReason` côté news (facts-to-news.mjs) : un fait
// d'événement en ligne porte le même socle qu'un fait d'actu — claim,
// source_url, source_date, confidence — avant même de parler de fenêtre.
// Sans ces gardes, un fait mal formé traverserait la matérialisation et
// n'échouerait qu'au `validate` suivant, noyé parmi les entrées saines.
test('un fait sans claim est refusé', () => {
  const { claim, ...sansClaim } = FACT;
  assert.throws(() => factToOnlineEvent(sansClaim), /claim/);
});

test('un fait sans source_url est refusé', () => {
  const { source_url, ...sansSource } = FACT;
  assert.throws(() => factToOnlineEvent(sansSource), /source_url/);
});

test('une date de source malformée est refusée', () => {
  assert.throws(() => factToOnlineEvent({ ...FACT, source_date: 'août 2026' }), /date/i);
});

test('une confiance inconnue est refusée', () => {
  assert.throws(() => factToOnlineEvent({ ...FACT, confidence: 'à peu près sûr' }), /confiance/i);
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

// --- materializeOnlineEvents : la fonction de matérialisation par lot ------
// Sœur de `materializeNews` (facts-to-news.mjs) : même discipline — filtrage
// par kind, idempotence par `processedFrom`, un seul conflit bloque le lot
// ENTIER. La différence : ici la validation par fait ET la frappe de l'id
// sont déjà portées par `factToOnlineEvent`, donc le lot se contente de la
// réutiliser au lieu de la dupliquer — voir le commentaire en tête de
// `materializeOnlineEvents`.

function onlineEventFact(overrides = {}) {
  return { ...FACT, ...overrides };
}

test('un fait online-event produit un squelette draft à rédiger', () => {
  const result = materializeOnlineEvents([onlineEventFact()], []);

  assert.equal(result.conflicts.length, 0);
  assert.equal(result.writes.length, 1);

  const { path, data } = result.writes[0];
  assert.match(data.id, /^online_[a-z0-9_]+$/);
  assert.equal(path, `content/online-events/${data.id}.json`);
  assert.equal(data.status, 'draft');
  assert.equal(data.needsRewrite, true);
  assert.equal(data.sourceClaim, FACT.claim);
});

test('rejouer le même fait ne réécrit rien — l’idempotence du run hebdomadaire', () => {
  const first = materializeOnlineEvents([onlineEventFact()], []);
  const existing = [{ path: first.writes[0].path, data: first.writes[0].data }];

  const second = materializeOnlineEvents([onlineEventFact()], existing);

  assert.equal(second.writes.length, 0);
  assert.equal(second.conflicts.length, 0);
  assert.equal(second.alreadyMaterialized.length, 1);
});

test('un fait rejoué depuis un AUTRE fichier d’inbox se réapparie quand même', () => {
  const first = materializeOnlineEvents(
    [{ ...onlineEventFact(), file: 'content/inbox/2026-08-03-a.facts.json' }],
    [],
  );
  const existing = [{ path: first.writes[0].path, data: first.writes[0].data }];

  const second = materializeOnlineEvents(
    [{ ...onlineEventFact(), file: 'content/inbox/2026-08-10-b.facts.json' }],
    existing,
  );

  assert.equal(second.writes.length, 0);
  assert.equal(second.alreadyMaterialized.length, 1);
});

test('un item déjà rédigé n’est jamais réécrasé par son squelette', () => {
  const skeleton = materializeOnlineEvents([onlineEventFact()], []).writes[0].data;
  const rewritten = {
    ...skeleton,
    title: { en: 'Sea race weekend', fr: 'Week-end courses en mer' },
    bonuses: [{ activity: { en: 'Sea races' }, label: { en: 'Double payout' } }],
    status: 'published',
  };
  delete rewritten.needsRewrite;

  const result = materializeOnlineEvents(
    [onlineEventFact()],
    [{ path: 'content/online-events/x.json', data: rewritten }],
  );

  assert.equal(result.writes.length, 0);
  assert.equal(result.alreadyMaterialized.length, 1);
});

test('les faits d’un autre kind sont écartés, jamais transformés', () => {
  const result = materializeOnlineEvents(
    [onlineEventFact({ kind: 'poi' }), onlineEventFact({ kind: 'news' }), onlineEventFact()],
    [],
  );

  assert.equal(result.writes.length, 1);
  assert.equal(result.skipped.length, 2);
});

test('deux faits distincts produisent deux ids distincts', () => {
  const result = materializeOnlineEvents(
    [onlineEventFact(), onlineEventFact({ claim: 'Triple RP on stunt jumps until August 20.' })],
    [],
  );

  assert.equal(result.writes.length, 2);
  assert.notEqual(result.writes[0].data.id, result.writes[1].data.id);
});

test('le même fait deux fois dans un lot n’écrit qu’un fichier', () => {
  const result = materializeOnlineEvents([onlineEventFact(), onlineEventFact()], []);

  assert.equal(result.writes.length, 1);
  assert.equal(result.conflicts.length, 0);
});

test('un fait sans fenêtre de fin bloque le lot au lieu de partir en schéma', () => {
  const { ends_at, ...sansFin } = onlineEventFact();

  const result = materializeOnlineEvents([sansFin], []);

  assert.equal(result.writes.length, 0);
  assert.equal(result.conflicts.length, 1);
  assert.match(result.conflicts[0].reason, /ends_at/);
});

test('un id frappé qui collisionne avec un autre processedFrom bloque tout le lot', () => {
  const minted = materializeOnlineEvents([onlineEventFact()], []).writes[0].data;
  const existing = [{
    path: 'content/online-events/collision.json',
    data: { ...minted, processedFrom: 'inbox:online-events:000000000000' },
  }];

  // Un second fait parfaitement valide accompagne le fautif : il ne doit pas
  // être écrit non plus.
  const result = materializeOnlineEvents(
    [onlineEventFact(), onlineEventFact({ claim: 'Un fait sain qui ne doit pas passer non plus.' })],
    existing,
  );

  assert.equal(result.conflicts.length, 1);
  assert.equal(result.writes.length, 0);
});

test('un conflit n’écrit rien du tout, même les faits sains du lot', () => {
  const result = materializeOnlineEvents(
    [onlineEventFact(), onlineEventFact({ claim: 'Fait sain.', game: 'gta4' })],
    [],
  );

  assert.equal(result.writes.length, 0);
  assert.equal(result.conflicts.length, 1);
});

test('les faits couverts sont rendus pour que l’inbox puisse être marquée', () => {
  const fresh = onlineEventFact();
  const already = onlineEventFact({ claim: 'Fait déjà matérialisé la semaine dernière.' });
  const existing = [{
    path: 'content/online-events/y.json',
    data: materializeOnlineEvents([already], []).writes[0].data,
  }];

  const result = materializeOnlineEvents([fresh, already], existing);

  // Les deux sont couverts : le neuf par une écriture, l'ancien par
  // réappariement. L'inbox doit marquer les DEUX, sinon le fait ancien
  // ressortirait comme « à traiter » à chaque run.
  assert.equal(result.covered.length, 2);
});
