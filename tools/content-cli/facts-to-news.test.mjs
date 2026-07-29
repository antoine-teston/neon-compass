import { test } from 'node:test';
import assert from 'node:assert/strict';
import { materializeNews, INBOX_SOURCE } from './facts-to-news.mjs';

function newsFact(overrides = {}) {
  return {
    claim: 'Un fait sourcé, rédigé par la veille, cité mot pour mot.',
    kind: 'news',
    source_url: 'https://example.test/article-a',
    source_date: '2026-07-27',
    confidence: 'multi-source',
    ...overrides,
  };
}

function existingItem(overrides = {}) {
  return {
    path: 'content/news/news_aaaaaaaa.json',
    data: {
      id: 'news_aaaaaaaa',
      category: 'announcement',
      title: { en: 'A' },
      body: { en: 'B' },
      publishedAt: '2026-07-01',
      status: 'draft',
      sources: ['https://example.test/x'],
      confidence: 'multi-source',
      ...overrides,
    },
  };
}

test('un fait news produit un squelette draft à rédiger', () => {
  const result = materializeNews([newsFact()], []);

  assert.equal(result.conflicts.length, 0);
  assert.equal(result.writes.length, 1);

  const { path, data } = result.writes[0];
  assert.match(data.id, /^news_[0-9a-f]{8}$/);
  assert.equal(path, `content/news/${data.id}.json`);
  assert.equal(data.status, 'draft');
  assert.equal(data.needsRewrite, true);
  assert.equal(data.publishedAt, '2026-07-27');
  assert.equal(data.confidence, 'multi-source');
  assert.deepEqual(data.sources, ['https://example.test/article-a']);
  assert.equal(data.sourceClaim, newsFact().claim);
  assert.match(data.processedFrom, new RegExp(`^${INBOX_SOURCE}:news:[0-9a-f]{12}$`));
});

test('le squelette ne recopie JAMAIS le fait brut dans title/body', () => {
  // Le fait cite ses sources mot pour mot, marques déposées comprises.
  // check-publishable scanne title/body de TOUTES les entrées, publiées ou non :
  // recopier le fait ferait échouer la CI dès la matérialisation.
  const claim = 'Rockstar et Take-Two ont annoncé GTA 6.';
  const result = materializeNews([newsFact({ claim })], []);

  const { data } = result.writes[0];
  assert.equal(data.sourceClaim, claim);
  for (const field of [data.title, data.body]) {
    for (const text of Object.values(field)) {
      assert.doesNotMatch(text, /Rockstar|Take-Two|GTA/i);
    }
  }
});

test('rejouer le même fait ne réécrit rien — l’idempotence du run hebdomadaire', () => {
  const first = materializeNews([newsFact()], []);
  const existing = [{ path: first.writes[0].path, data: first.writes[0].data }];

  const second = materializeNews([newsFact()], existing);

  assert.equal(second.writes.length, 0);
  assert.equal(second.conflicts.length, 0);
  assert.equal(second.alreadyMaterialized.length, 1);
});

test('un fait rejoué depuis un AUTRE fichier d’inbox se réapparie quand même', () => {
  // La clé porte le contenu du fait, pas son fichier d'origine : un fait
  // re-signalé la semaine suivante ne doit pas produire un doublon dans le fil.
  const first = materializeNews([{ ...newsFact(), file: 'content/inbox/2026-07-21-a.facts.json' }], []);
  const existing = [{ path: first.writes[0].path, data: first.writes[0].data }];

  const second = materializeNews([{ ...newsFact(), file: 'content/inbox/2026-08-03-b.facts.json' }], existing);

  assert.equal(second.writes.length, 0);
  assert.equal(second.alreadyMaterialized.length, 1);
});

test('un item déjà rédigé n’est jamais réécrasé par son squelette', () => {
  const skeleton = materializeNews([newsFact()], []).writes[0].data;
  const rewritten = {
    ...skeleton,
    title: { en: 'Rewritten', fr: 'Rédigé' },
    body: { en: 'Rewritten body', fr: 'Corps rédigé' },
    status: 'published',
  };
  delete rewritten.needsRewrite;

  const result = materializeNews([newsFact()], [{ path: 'content/news/x.json', data: rewritten }]);

  assert.equal(result.writes.length, 0);
  assert.equal(result.alreadyMaterialized.length, 1);
});

test('les faits d’un autre kind sont écartés, jamais transformés', () => {
  const result = materializeNews(
    [newsFact({ kind: 'poi' }), newsFact({ kind: 'cheat' }), newsFact()],
    [],
  );

  assert.equal(result.writes.length, 1);
  assert.equal(result.skipped.length, 2);
});

test('deux faits distincts produisent deux ids distincts', () => {
  const result = materializeNews(
    [newsFact(), newsFact({ claim: 'Un autre fait, tout aussi sourcé.' })],
    [],
  );

  assert.equal(result.writes.length, 2);
  assert.notEqual(result.writes[0].data.id, result.writes[1].data.id);
});

test('le même fait deux fois dans un lot n’écrit qu’un fichier', () => {
  // Régression possible : sans tenue de l'index au fil du lot, deux faits
  // identiques du MÊME run produiraient deux fichiers de même id.
  const result = materializeNews([newsFact(), newsFact()], []);

  assert.equal(result.writes.length, 1);
  assert.equal(result.conflicts.length, 0);
});

test('une date de source malformée bloque le lot au lieu de partir en schéma', () => {
  const result = materializeNews([newsFact({ source_date: 'juillet 2026' })], []);

  assert.equal(result.writes.length, 0);
  assert.equal(result.conflicts.length, 1);
  assert.match(result.conflicts[0].reason, /date/i);
});

test('un fait sans source ne devient pas un item', () => {
  const result = materializeNews([newsFact({ source_url: '' })], []);

  assert.equal(result.writes.length, 0);
  assert.equal(result.conflicts.length, 1);
});

test('les quatre confiances du contrat data-scout sont acceptées', () => {
  // Un conflit bloque le lot ENTIER : une valeur que la veille émet mais que la
  // transformation ignore ferait perdre toute la récolte de la semaine, sans
  // que rien ne dise pourquoi. Ce test est le seul endroit où les deux
  // définitions se regardent (.claude/agents/data-scout.md).
  const confidences = ['confirmed-official', 'multi-source', 'single-source', 'rumor'];
  const facts = confidences.map((confidence) => newsFact({ confidence, claim: `Fait ${confidence}.` }));

  const result = materializeNews(facts, []);

  assert.equal(result.conflicts.length, 0);
  assert.equal(result.writes.length, confidences.length);
});

test('une confiance inconnue bloque le lot', () => {
  const result = materializeNews([newsFact({ confidence: 'à peu près sûr' })], []);

  assert.equal(result.writes.length, 0);
  assert.equal(result.conflicts.length, 1);
  assert.match(result.conflicts[0].reason, /confiance|confidence/i);
});

test('un id frappé qui collisionne avec un autre processedFrom bloque tout le lot', () => {
  const minted = materializeNews([newsFact()], []).writes[0].data;
  const existing = [{
    path: 'content/news/collision.json',
    data: { ...minted, processedFrom: 'inbox:news:000000000000' },
  }];

  // Un second fait parfaitement valide accompagne le fautif : il ne doit pas
  // être écrit non plus. Un lot à moitié appliqué laisse le dépôt dans un état
  // que personne ne peut raisonner.
  const result = materializeNews(
    [newsFact(), newsFact({ claim: 'Un fait sain qui ne doit pas passer non plus.' })],
    existing,
  );

  assert.equal(result.conflicts.length, 1);
  assert.equal(result.writes.length, 0);
});

test('un conflit n’écrit rien du tout, même les faits sains du lot', () => {
  const result = materializeNews(
    [newsFact(), newsFact({ claim: 'Fait sain.', source_date: 'pas une date' })],
    [],
  );

  assert.equal(result.writes.length, 0);
  assert.equal(result.conflicts.length, 1);
});

test('les faits couverts sont rendus pour que l’inbox puisse être marquée', () => {
  const fresh = newsFact();
  const already = newsFact({ claim: 'Fait déjà matérialisé la semaine dernière.' });
  const existing = [{ path: 'content/news/y.json', data: materializeNews([already], []).writes[0].data }];

  const result = materializeNews([fresh, already], existing);

  // Les deux sont couverts par un item : le neuf par une écriture, l'ancien par
  // réappariement. L'inbox doit marquer les DEUX, sinon le fait ancien
  // ressortirait comme « à traiter » à chaque run.
  assert.equal(result.covered.length, 2);
});
