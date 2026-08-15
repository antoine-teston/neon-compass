import { test } from 'node:test';
import assert from 'node:assert/strict';
import { policyFor, assertAllowed, parseFeed, htmlToText, feedURLFor, explicitlyForbidden } from './source-policy.mjs';

// `explicitlyForbidden` répond à une question plus ÉTROITE que `policyFor` :
// non pas « peut-on fetcher ? » mais « le registre a-t-il BANNI cet hôte ? ».
// La distinction porte le contrôle d'inbox : un fait ne peut pas citer un hôte
// banni, mais un hôte simplement inconnu n'invalide pas un fait — le
// matérialiseur refuse ce que le registre a tranché, il ne s'invente pas la
// police de tout l'Internet.

test('un hôte banni est nommé, alias compris', () => {
  assert.ok(explicitlyForbidden('https://www.rockstargames.com/VI'));
  // La faute réelle du 21/07 : un fait de cheats citait gtacodes.io.
  assert.ok(explicitlyForbidden('https://gtacodes.io/community-verified'));
  // Les alias ne contournent pas le ban par simple orthographe.
  assert.ok(explicitlyForbidden('https://old.reddit.com/r/GTA6/x'));
});

test('un hôte inconnu n’est PAS banni — il est seulement non fetchable', () => {
  assert.equal(explicitlyForbidden('https://example.test/article'), null);
  // Une URL illisible n'est pas le sujet de CE contrôle.
  assert.equal(explicitlyForbidden('pas-une-url'), null);
});

test('les domaines dont le robots.txt nous autorise passent', () => {
  for (const url of [
    'https://www.gtaboom.com/gta-6-cheats-9nd6',
    'https://leonidaverse.com/en/news',
    'https://gta6.gg/news/',
  ]) {
    assert.equal(policyFor(url).mode, 'allow', url);
  }
});

test('rockstargames est INTERDIT : son robots.txt nomme ClaudeBot', () => {
  const policy = policyFor('https://www.rockstargames.com/newswire');

  assert.equal(policy.mode, 'forbidden');
  assert.match(policy.reason, /ClaudeBot/);
});

test('reddit est INTERDIT sur toutes ses formes d’hôte', () => {
  for (const url of [
    'https://www.reddit.com/r/GTA6/new',
    'https://reddit.com/r/GTA6',
    'https://old.reddit.com/r/GTA6',
    'https://www.reddit.com/r/GTA6/.rss',
  ]) {
    const policy = policyFor(url);
    assert.equal(policy.mode, 'forbidden', url);
    assert.match(policy.reason, /API/i, url);
  }
});

test('fandom passe par son API, jamais par le HTML', () => {
  const policy = policyFor('https://gta.fandom.com/wiki/Grand_Theft_Auto_VI');

  assert.equal(policy.mode, 'api');
  assert.ok(policy.api.includes('api.php'));
});

test('un domaine inconnu est refusé par défaut — liste blanche, pas liste noire', () => {
  // La règle du spec est une liste blanche stricte. Un défaut permissif la
  // transformerait en liste noire au premier domaine oublié.
  const policy = policyFor('https://un-site-quelconque.example/article');

  assert.equal(policy.mode, 'forbidden');
  assert.match(policy.reason, /liste blanche/i);
});

test('assertAllowed lève avec la raison, pour que le refus soit lisible', () => {
  assert.throws(() => assertAllowed('https://www.reddit.com/r/GTA6'), /reddit|API/i);
  assert.doesNotThrow(() => assertAllowed('https://www.gtaboom.com/x'));
});

test('une URL malformée est refusée, pas interprétée', () => {
  assert.equal(policyFor('pas une url').mode, 'forbidden');
  assert.throws(() => assertAllowed('pas une url'));
});

test('le flux d’un domaine est connu sans avoir à le deviner', () => {
  assert.equal(feedURLFor('https://www.gtaboom.com/quoi-que-ce-soit'), 'https://www.gtaboom.com/feed.xml');
  assert.equal(feedURLFor('https://leonidaverse.com/en'), 'https://leonidaverse.com/news-sitemap.xml');
  // Depuis le 2026-08-15 le flux WordPress de gta6.gg est déclaré : il répond
  // 200 mais était VIDE ce jour-là (0 item, lastBuildDate au 22/03). On le lit
  // quand même — son silence devient visible dans feeds.json au lieu que la
  // source soit simplement absente de tous les rapports.
  assert.equal(feedURLFor('https://gta6.gg/news/'), 'https://gta6.gg/feed/');
});

test('parseFeed lit un RSS 2.0, CDATA compris', () => {
  const rss = `<?xml version="1.0"?><rss version="2.0"><channel>
    <item><title><![CDATA[Un titre & son esperluette]]></title>
      <link>https://www.gtaboom.com/a</link>
      <pubDate>Wed, 29 Jul 2026 08:18:00 GMT</pubDate></item>
    <item><title>Un second</title>
      <link>https://www.gtaboom.com/b</link>
      <pubDate>Tue, 28 Jul 2026 15:26:00 GMT</pubDate></item>
  </channel></rss>`;

  const items = parseFeed(rss);

  assert.equal(items.length, 2);
  assert.equal(items[0].title, 'Un titre & son esperluette');
  assert.equal(items[0].link, 'https://www.gtaboom.com/a');
  assert.equal(items[0].date, '2026-07-29');
  assert.equal(items[1].date, '2026-07-28');
});

test('parseFeed lit un Atom', () => {
  const atom = `<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
    <entry><title>Titre atom</title>
      <link href="https://example.test/a"/>
      <updated>2026-07-29T08:18:00Z</updated></entry>
  </feed>`;

  const items = parseFeed(atom);

  assert.equal(items.length, 1);
  assert.equal(items[0].title, 'Titre atom');
  assert.equal(items[0].link, 'https://example.test/a');
  assert.equal(items[0].date, '2026-07-29');
});

test('parseFeed lit un news-sitemap', () => {
  const sitemap = `<?xml version="1.0"?>
  <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">
    <url><loc>https://leonidaverse.com/en/news/x</loc>
      <news:news><news:publication_date>2026-06-26T10:00:00+00:00</news:publication_date>
      <news:title>Un titre de sitemap</news:title></news:news></url>
  </urlset>`;

  const items = parseFeed(sitemap);

  assert.equal(items.length, 1);
  assert.equal(items[0].title, 'Un titre de sitemap');
  assert.equal(items[0].date, '2026-06-26');
});

test('parseFeed rend un tableau vide sur une entrée illisible, sans lever', () => {
  // Un flux qui change de forme ne doit pas faire tomber un run entier : la
  // veille continue avec les autres sources, et le compte-rendu le dira.
  assert.deepEqual(parseFeed('<html>pas un flux</html>'), []);
  assert.deepEqual(parseFeed(''), []);
});

test('htmlToText retire scripts, styles et balises', () => {
  const html = `<html><head><style>.a{color:red}</style><script>var x = 1 < 2;</script></head>
    <body><h1>Titre</h1><p>Un paragraphe avec &amp; une entité.</p>
    <nav>menu</nav></body></html>`;

  const text = htmlToText(html);

  assert.match(text, /Titre/);
  assert.match(text, /Un paragraphe avec & une entité\./);
  assert.doesNotMatch(text, /color:red/);
  assert.doesNotMatch(text, /var x/);
});

test('htmlToText ne rend pas un pavé illisible', () => {
  const text = htmlToText('<p>Un</p>\n\n\n\n<p>Deux</p>');
  assert.doesNotMatch(text, /\n{3,}/);
});
