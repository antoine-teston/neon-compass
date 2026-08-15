import { test } from 'node:test';
import assert from 'node:assert/strict';
import { problemsFor, problemsIfPublished } from './publishable.mjs';

// La confiance se PROUVE, elle ne se déclare pas. Le 2026-08-15, les neuf items
// d'actu en `multi-source` du dépôt citaient chacun UNE seule URL : la confiance
// était un jugement du modèle, invérifiable après coup. Ces tests fixent la
// règle qui rend le mot honnête : `multi-source` exige que `sources[]` porte au
// moins deux hôtes distincts — deux URL du même site sont la même voix.

function newsEntry(overrides = {}) {
  return {
    kind: 'news',
    file: 'content/news/news_00000000.json',
    data: {
      id: 'news_00000000',
      category: 'announcement',
      title: { en: 'A headline in our own words' },
      body: { en: 'Body written by us.' },
      publishedAt: '2026-08-01',
      status: 'published',
      sources: ['https://www.gtaboom.com/article'],
      confidence: 'multi-source',
      ...overrides,
    },
  };
}

test('publié en multi-source avec une seule source : refusé', () => {
  const problems = problemsFor(newsEntry());

  assert.equal(problems.length, 1);
  assert.match(problems[0], /multi-source/);
  assert.match(problems[0], /2 distinct hosts/);
});

test('deux URL du même hôte ne sont PAS une corroboration — www ne compte pas', () => {
  // Le contournement évident : citer le même site deux fois, une fois avec
  // `www.` et une fois sans. C'est la même voix.
  const problems = problemsFor(
    newsEntry({ sources: ['https://www.gtaboom.com/article', 'https://gtaboom.com/echo'] }),
  );

  assert.equal(problems.length, 1);
  assert.match(problems[0], /multi-source/);
});

test('deux hôtes distincts prouvent le multi-source', () => {
  const problems = problemsFor(
    newsEntry({ sources: ['https://www.gtaboom.com/article', 'https://leonidaverse.com/en/news/echo'] }),
  );

  assert.deepEqual(problems, []);
});

test('un brouillon multi-source mal sourcé passe — mais problemsIfPublished le voit', () => {
  // Même régime que toutes les règles de publication : le brouillon vit, la
  // console demande « passerait-il ? » via la simulation.
  const draft = newsEntry({ status: 'draft' });

  assert.deepEqual(problemsFor(draft), []);
  assert.match(problemsIfPublished(draft).join('\n'), /multi-source/);
});

test('les événements en ligne sont soumis à la même preuve', () => {
  const problems = problemsFor({
    kind: 'online-events',
    file: 'content/online-events/online_00000000.json',
    data: {
      id: 'online_00000000',
      title: { en: 'Weekly window' },
      status: 'published',
      sources: ['https://www.gtaboom.com/gta-online-weekly-updates'],
      confidence: 'multi-source',
    },
  });

  assert.equal(problems.length, 1);
  assert.match(problems[0], /multi-source/);
});

test('single-source avec une seule URL : rien à redire', () => {
  const problems = problemsFor(newsEntry({ confidence: 'single-source' }));

  assert.deepEqual(problems, []);
});

test('une URL imparsable ne fait pas planter le contrôle — elle compte comme un hôte', () => {
  const problems = problemsFor(
    newsEntry({ sources: ['pas-une-url', 'https://leonidaverse.com/en/news/echo'] }),
  );

  assert.deepEqual(problems, []);
});
