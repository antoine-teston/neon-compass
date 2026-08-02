import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { factToOnlineEvent, materializeOnlineEvents, windowDiscriminant, revisedFields } from './facts-to-online-event.mjs';
import { identityKey } from '../basemap/gtav-poi-ids.mjs';
import { INBOX_SOURCE } from './facts-to-news.mjs';

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
  return identityKey(INBOX_SOURCE, 'online-events', windowDiscriminant(fact));
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

test("l'identité change si la FENÊTRE change de début", () => {
  assert.notEqual(expectedKey(FACT), expectedKey({ ...FACT, starts_at: '2026-08-13T09:00:00Z' }));
});

test("l'identité ne change PAS si seul le contenu du fait change", () => {
  // C'est le cœur du choix : une fenêtre qu'on relit reste la même fenêtre.
  // Hacher le claim en faisait une entrée neuve à chaque prolongation.
  assert.equal(expectedKey(FACT), expectedKey({ ...FACT, claim: 'autre chose', ends_at: '2026-08-20T09:00:00Z' }));
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
// La liste des champs permis est LUE DANS LE SCHÉMA, pas recopiée ici : une liste
// recopiée dérive au premier champ ajouté, et c'est ce qui est arrivé — le test a
// échoué sur `rewards` alors que le schéma le déclarait. Le schéma est en
// `additionalProperties: false`, il fait donc autorité.
test('aucun champ hors schéma n’est produit', () => {
  const schema = JSON.parse(
    readFileSync(new URL('../../content/schema/online-event.schema.json', import.meta.url), 'utf8'),
  );
  const permis = new Set(Object.keys(schema.properties));
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
    bonuses: [{ activity: { en: 'Sea races' }, multiplier: 2, includesRP: false }],
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

test('deux fenêtres distinctes produisent deux ids distincts', () => {
  const result = materializeOnlineEvents(
    [onlineEventFact(), onlineEventFact({ starts_at: '2026-08-13T09:00:00Z', ends_at: '2026-08-20T09:00:00Z' })],
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
    [
      onlineEventFact(),
      onlineEventFact({ starts_at: '2026-08-13T09:00:00Z', ends_at: '2026-08-20T09:00:00Z' }),
    ],
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

// --- Faits STRUCTURÉS (weekly-hub.mjs) ------------------------------------
//
// Un fait qui porte déjà ses bonus et ses remises n'a plus rien à faire rédiger.
// C'est tout l'intérêt de l'extraction déterministe : ce que la source publie en
// tableau ne traverse aucun modèle.

const STRUCTURED = {
  ...FACT,
  claim: 'Fenêtre du mode en ligne du 2026-07-30 au 2026-08-05 : 1 bonus et 1 remise.',
  sources: ['https://www.gtaboom.com/gta-online-weekly-updates', 'https://www.gtaboom.com/semaine'],
  title: { en: 'Weekly update — 2026-07-30', fr: 'Mise à jour hebdomadaire — 2026-07-30' },
  bonuses: [{ activity: { en: 'Fleeca Heist Finale' }, multiplier: 2, includesRP: true }],
  discounts: [{ item: { en: 'Karin Kuruma' }, percent: 60 }],
  source_prose: 'Fleeca Heist Finale — 2x GTA$ — First completion pays double GTA$ through August 5.',
};

test('un fait structuré produit un événement complet, sans rédaction à faire', () => {
  const event = factToOnlineEvent(STRUCTURED);
  assert.equal(event.needsRewrite, false);
  assert.equal(event.status, 'draft');
  assert.deepEqual(event.bonuses, STRUCTURED.bonuses);
  assert.deepEqual(event.discounts, STRUCTURED.discounts);
  assert.equal(event.title.fr, 'Mise à jour hebdomadaire — 2026-07-30');
});

test('les deux URL de la semaine sont conservées comme sources', () => {
  assert.deepEqual(factToOnlineEvent(STRUCTURED).sources, STRUCTURED.sources);
});

test('sourceClaim porte la prose de la source, pas le résumé', () => {
  // C'est ce qui donne sa substance à `check-originality.mjs` : comparer un champ
  // rédigé à un résumé qu'on a soi-même écrit ne prouve rien.
  assert.equal(factToOnlineEvent(STRUCTURED).sourceClaim, STRUCTURED.source_prose);
  assert.equal(factToOnlineEvent(FACT).sourceClaim, FACT.claim);
});

test('un squelette reste un squelette', () => {
  const event = factToOnlineEvent(FACT);
  assert.equal(event.needsRewrite, true);
  assert.deepEqual(event.bonuses, []);
});

test('un fait structuré mal formé échoue ICI, pas au validate suivant', () => {
    assert.throws(() => factToOnlineEvent({ ...STRUCTURED, bonuses: [{ activity: { en: 'X' } }] }), /ni multiplier ni percentBonus/);
    assert.throws(() => factToOnlineEvent({ ...STRUCTURED, bonuses: [{ activity: { en: 'X' }, multiplier: 2, percentBonus: 15 }] }), /les deux s.excluent/);
    assert.throws(() => factToOnlineEvent({ ...STRUCTURED, bonuses: [{ activity: { en: 'X' }, multiplier: 1 }] }), /entier 2-10/);
    assert.throws(() => factToOnlineEvent({ ...STRUCTURED, bonuses: [{ activity: { en: 'X' }, multiplier: 2, until: '12 août' }] }), /AAAA-MM-JJ/);
  assert.throws(() => factToOnlineEvent({ ...STRUCTURED, bonuses: 'deux fois plus' }), /bonuses : tableau attendu/);
  assert.throws(() => factToOnlineEvent({ ...STRUCTURED, discounts: [{ item: { en: 'X' }, percent: 0 }] }), /entier 1-100/);
  assert.throws(() => factToOnlineEvent({ ...STRUCTURED, discounts: [{ item: { en: 'X' }, percent: 12.5 }] }), /entier 1-100/);
    assert.throws(() => factToOnlineEvent({ ...STRUCTURED, bonuses: [{ activity: {}, multiplier: 2 }] }), /avec au moins/);
});

test('un fait structuré traverse la matérialisation par lot', () => {
  const result = materializeOnlineEvents([STRUCTURED], []);
  assert.equal(result.conflicts.length, 0);
  assert.equal(result.writes.length, 1);
  assert.equal(result.writes[0].data.needsRewrite, false);
  assert.equal(result.writes[0].data.discounts[0].percent, 60);
});

// --- Une fenêtre MUTE : identité par le début, révision par la fin ---------
//
// La source le dit elle-même : Rockstar prolonge parfois un événement. C'est le
// seul kind du dépôt dont le contenu peut changer après publication.

test('l’identité tient au DÉBUT de fenêtre, pas à son contenu', () => {
  const base = { ...STRUCTURED };
  const prolongé = { ...base, ends_at: '2026-08-20T09:00:00Z', claim: 'autre claim, autre fin' };
  // Une fin qui bouge, un claim qui bouge : la MÊME entrée.
  assert.equal(factToOnlineEvent(base).id, factToOnlineEvent(prolongé).id);
  assert.equal(factToOnlineEvent(base).processedFrom, factToOnlineEvent(prolongé).processedFrom);
});

test('un début différent est une autre fenêtre — la phase 2 a son entrée', () => {
  const phase2 = { ...STRUCTURED, starts_at: '2026-08-13T09:00:00Z', ends_at: '2026-08-20T09:00:00Z' };
  assert.notEqual(factToOnlineEvent(STRUCTURED).id, factToOnlineEvent(phase2).id);
});

test('un autre jeu est une autre fenêtre, même début', () => {
  const leonida = { ...STRUCTURED, game: 'leonida' };
  assert.notEqual(windowDiscriminant(STRUCTURED), windowDiscriminant(leonida));
});

test('une fenêtre prolongée est RÉVISÉE, pas doublée', () => {
  const existing = [{ path: 'content/online-events/x.json', data: materializeOnlineEvents([STRUCTURED], []).writes[0].data }];
  const prolongé = { ...STRUCTURED, ends_at: '2026-08-20T09:00:00Z' };

  const result = materializeOnlineEvents([prolongé], existing);

  assert.equal(result.writes.length, 0, 'aucune entrée neuve');
  assert.equal(result.updates.length, 1);
  assert.deepEqual(result.updates[0].changes, ['endsAt']);
  assert.equal(result.updates[0].data.endsAt, '2026-08-20T09:00:00Z');
  assert.equal(result.updates[0].data.id, existing[0].data.id);
  assert.equal(result.updates[0].path, existing[0].path);
});

test('une entrée PUBLIÉE garde son statut quand sa fenêtre est corrigée', () => {
  // C'est tout l'intérêt : un compte à rebours faux en ligne doit se corriger en
  // ligne. Ce que la révision ne fait JAMAIS, c'est publier quelque chose.
  const published = { ...materializeOnlineEvents([STRUCTURED], []).writes[0].data, status: 'published' };
  const result = materializeOnlineEvents([{ ...STRUCTURED, ends_at: '2026-08-20T09:00:00Z' }], [
    { path: 'content/online-events/x.json', data: published },
  ]);
  assert.equal(result.updates[0].data.status, 'published');

  const draft = materializeOnlineEvents([STRUCTURED], []).writes[0].data;
  const stillDraft = materializeOnlineEvents([{ ...STRUCTURED, ends_at: '2026-08-20T09:00:00Z' }], [
    { path: 'content/online-events/y.json', data: draft },
  ]);
  assert.equal(stillDraft.updates[0].data.status, 'draft');
});

test('une rédaction humaine garde ses textes, mais pas sa fenêtre', () => {
  // Un squelette rédigé à la main voit `needsRewrite` SUPPRIMÉ : c'est ce qui
  // distingue « quelqu'un a pris le relais » de « la machine a tout écrit ».
  const skeleton = materializeOnlineEvents([FACT], []).writes[0].data;
  const rédigé = { ...skeleton, title: { en: 'Sea race weekend', fr: 'Courses en mer' }, status: 'published' };
  delete rédigé.needsRewrite;

  const result = materializeOnlineEvents([{ ...FACT, ends_at: '2026-08-20T09:00:00Z' }], [
    { path: 'content/online-events/z.json', data: rédigé },
  ]);

  // La fenêtre est corrigée — personne d'autre que la machine ne l'écrit.
  assert.deepEqual(result.updates[0].changes, ['endsAt']);
  // Le titre écrit à la main survit, et le statut aussi.
  assert.equal(result.updates[0].data.title.fr, 'Courses en mer');
  assert.equal(result.updates[0].data.status, 'published');
});

test('un squelette non rédigé ne voit pas ses textes vides remplacés', () => {
  const skeleton = materializeOnlineEvents([FACT], []).writes[0].data;
  assert.equal(skeleton.needsRewrite, true);
  const result = materializeOnlineEvents([{ ...FACT, bonuses: STRUCTURED.bonuses }], [
    { path: 'content/online-events/z.json', data: skeleton },
  ]);
  // Le fait devient structuré, mais l'entrée existante est encore à rédiger :
  // seule la fenêtre est révisable, et elle n'a pas bougé.
  assert.equal(result.updates.length, 0);
  assert.equal(result.alreadyMaterialized.length, 1);
});

test('une entrée déjà à jour n’est pas réécrite', () => {
  const existing = [{ path: 'content/online-events/x.json', data: materializeOnlineEvents([STRUCTURED], []).writes[0].data }];
  const result = materializeOnlineEvents([STRUCTURED], existing);
  assert.equal(result.writes.length, 0);
  assert.equal(result.updates.length, 0);
  assert.equal(result.alreadyMaterialized.length, 1);
});

test('revisedFields ignore le statut et l’identité', () => {
  const a = materializeOnlineEvents([STRUCTURED], []).writes[0].data;
  assert.deepEqual(revisedFields(a, { ...a, status: 'published' }), []);
  assert.deepEqual(revisedFields(a, { ...a, endsAt: 'X', confidence: 'single-source' }).sort(), ['confidence', 'endsAt']);
});

test('un champ révisable qui disparaît est retiré, pas laissé en place', () => {
  // Un podium retiré par la source doit disparaître de la carte, pas y rester.
  const withPodium = { ...materializeOnlineEvents([STRUCTURED], []).writes[0].data, podiumVehicle: { en: 'Karin Kuruma' } };
  const result = materializeOnlineEvents([STRUCTURED], [{ path: 'content/online-events/x.json', data: withPodium }]);
  assert.deepEqual(result.updates[0].changes, ['podiumVehicle']);
  assert.equal('podiumVehicle' in result.updates[0].data, false);
});
