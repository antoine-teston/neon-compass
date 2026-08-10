import { test } from 'node:test';
import assert from 'node:assert/strict';
import { materializeNews, INBOX_SOURCE } from './facts-to-news.mjs';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ICI = dirname(fileURLToPath(import.meta.url));

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
  // source_url distincte pour le second fait : depuis le contrôle de
  // convergence, deux faits de même source_url et de kind news n'en
  // produisent qu'un. Deux faits VRAIMENT distincts viennent donc de deux
  // articles distincts, pas seulement de deux claims sur le même article.
  const result = materializeNews(
    [newsFact(), newsFact({ source_url: 'https://example.test/article-b', claim: 'Un autre fait, tout aussi sourcé.' })],
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
  //
  // Une source_url distincte par confiance : depuis le contrôle de
  // convergence, deux faits de même source_url et de kind news n'en
  // produisent qu'un, ce qui masquerait ici trois des quatre écritures
  // attendues.
  const confidences = ['confirmed-official', 'multi-source', 'single-source', 'rumor'];
  const facts = confidences.map((confidence) => newsFact({
    confidence,
    claim: `Fait ${confidence}.`,
    source_url: `https://example.test/${confidence}`,
  }));

  const result = materializeNews(facts, []);

  assert.equal(result.conflicts.length, 0);
  assert.equal(result.writes.length, confidences.length);
});

test('le jeu du fait est porté dans le squelette, et vaut leonida par défaut', () => {
  const withGame = materializeNews([newsFact({ game: 'gtav' })], []);
  assert.equal(withGame.writes[0].data.game, 'gtav');

  const without = materializeNews([newsFact({ claim: 'Un fait sans jeu déclaré.' })], []);
  assert.equal(without.writes[0].data.game, 'leonida');
});

test('un jeu inconnu bloque le lot', () => {
  const result = materializeNews([newsFact({ game: 'gta4' })], []);

  assert.equal(result.writes.length, 0);
  assert.equal(result.conflicts.length, 1);
  assert.match(result.conflicts[0].reason, /jeu/i);
});

test('une confiance inconnue bloque le lot', () => {
  const result = materializeNews([newsFact({ confidence: 'à peu près sûr' })], []);

  assert.equal(result.writes.length, 0);
  assert.equal(result.conflicts.length, 1);
  assert.match(result.conflicts[0].reason, /confiance|confidence/i);
});

test('un id frappé qui collisionne avec un autre processedFrom bloque tout le lot', () => {
  const minted = materializeNews([newsFact()], []).writes[0].data;
  // sources DIFFÉRENTE de celle des faits entrants, id INCHANGÉ (celui qui doit
  // collisionner) : depuis le contrôle de convergence, une source_url déjà
  // portée écarte le fait avant même la frappe d'id — la collision qu'on veut
  // tester n'aurait jamais lieu si cette entrée portait la même URL.
  const existing = [{
    path: 'content/news/collision.json',
    data: { ...minted, sources: ['https://example.test/autre-article'], processedFrom: 'inbox:news:000000000000' },
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
  // source_url distincte pour fresh : depuis le contrôle de convergence, deux
  // faits de même source_url et de kind news n'en produisent qu'un — fresh
  // serait écarté au lieu d'être compté comme couvert par écriture.
  const fresh = newsFact({ source_url: 'https://example.test/article-fraiche' });
  const already = newsFact({ claim: 'Fait déjà matérialisé la semaine dernière.' });
  const existing = [{ path: 'content/news/y.json', data: materializeNews([already], []).writes[0].data }];

  const result = materializeNews([fresh, already], existing);

  // Les deux sont couverts par un item : le neuf par une écriture, l'ancien par
  // réappariement. L'inbox doit marquer les DEUX, sinon le fait ancien
  // ressortirait comme « à traiter » à chaque run.
  assert.equal(result.covered.length, 2);
});

// ---------------------------------------------------------------------------
// Le contrôle de convergence
//
// Il tourne ICI, après le merge, et pas à la récolte : deux sessions
// concurrentes liraient toutes deux « URL non couverte » avant que l'une
// n'écrive. Constaté les 08, 09 et 10 août 2026.
// ---------------------------------------------------------------------------

test('deux lectures du même article ne produisent qu’une entrée', () => {
  // La panne exacte de la PR #83 : deux sessions, deux claims, un seul article.
  const a = newsFact({ claim: 'Le PDG a déclaré que les précommandes dépassaient les prévisions.' });
  const b = newsFact({ claim: 'Lors de ses résultats, l’éditeur a indiqué que les précommandes dépassaient ses prévisions.' });
  const { writes, ecartes } = materializeNews([a, b], []);

  assert.equal(writes.length, 1, 'un article, une entrée');
  assert.equal(ecartes.length, 1);
  assert.equal(ecartes[0].url, a.source_url);
  assert.match(ecartes[0].raison, /déjà couverte/);
});

test('un écart NOMME le claim qu’il jette', () => {
  // Une URL peut légitimement porter deux sujets. Le contrôle en sacrifie un ;
  // il ne doit pas le perdre en silence.
  const a = newsFact({ claim: 'Sony a réinscrit le jeu sur sa page éditoriale.' });
  const b = newsFact({ claim: 'Un ancien animateur juge le jeu achevé à 80-90 %.' });
  const { ecartes } = materializeNews([a, b], []);

  assert.equal(ecartes.length, 1);
  assert.match(ecartes[0].claim, /ancien animateur/);
});

test('une URL déjà portée par une entrée EXISTANTE écarte le fait', () => {
  const existant = existingItem({ id: 'news_deja', sources: ['https://example.test/article-a'] });
  const { writes, ecartes } = materializeNews([newsFact()], [existant]);

  assert.equal(writes.length, 0);
  assert.equal(ecartes[0].par, 'news_deja', 'le rapport nomme l’entrée qui la portait déjà');
});

test('deux articles DIFFÉRENTS produisent bien deux entrées', () => {
  const a = newsFact({ source_url: 'https://example.test/un' });
  const b = newsFact({ source_url: 'https://example.test/deux', claim: 'Un autre fait.' });
  const { writes, ecartes } = materializeNews([a, b], []);

  assert.equal(writes.length, 2);
  assert.equal(ecartes.length, 0);
});

test('rejeu du réel : aucune URL n’est matérialisée deux fois', () => {
  // Les vrais faits du dépôt, pas une reconstitution. 12 URLs y sont dupliquées
  // par les doubles runs des 08, 09 et 10 août, plus quatre doublons INTRA-run
  // des 06 et 07 — l'agent se répète aussi tout seul.
  const inbox = join(ICI, '..', '..', 'content', 'inbox');
  const facts = readdirSync(inbox)
    .filter((f) => f.endsWith('.facts.json'))
    .sort()
    .flatMap((f) => JSON.parse(readFileSync(join(inbox, f), 'utf8')).facts ?? []);

  const { writes } = materializeNews(facts, []);
  const urls = writes.map((w) => w.data.sources[0]);
  assert.equal(new Set(urls).size, urls.length, 'deux entrées produites pour une même URL');
});
