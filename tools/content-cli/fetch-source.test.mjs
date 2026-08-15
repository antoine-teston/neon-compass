import { test } from 'node:test';
import assert from 'node:assert/strict';
import { diagnosis, harvestSlug, recentEntries } from './fetch-source.mjs';

// Un 403 a deux causes opposées, et le projet s'est trompé de cause trois fois :
// deux runs de juillet ont accusé les sources (elles répondaient 200), le run du
// 3 août a pris un 403 sur les quatre domaines alors que c'était la passerelle
// de sortie de la session. Ces tests fixent la seule chose qui compte dans le
// message : l'action qu'il fait entreprendre.

test('sortie ouverte : le refus est imputé à la source, et on va lire son robots.txt', () => {
  const text = diagnosis({ message: 'HTTP 403 sur https://www.gtaboom.com/x', egressOpen: true });

  assert.match(text, /HTTP 403 sur https:\/\/www\.gtaboom\.com\/x/);
  assert.match(text, /vient de la source/i);
  assert.match(text, /robots\.txt/);
  // Surtout pas : c'est le contresens qui coûterait une source retirée à tort.
  assert.doesNotMatch(text, /passerelle/i);
});

test('sortie bloquée : le refus n’est PAS imputé aux sources, et on ne touche pas au registre', () => {
  const text = diagnosis({ message: 'HTTP 403 sur https://www.gtaboom.com/x', egressOpen: false });

  assert.match(text, /SORTIE RÉSEAU BLOQUÉE/);
  assert.match(text, /n'est PAS un refus des sources/);
  assert.match(text, /pas toucher au registre/);
});

test('un proxy déclaré est nommé — le fetch de Node l’ignore, ce qui trompe l’opérateur', () => {
  const text = diagnosis({
    message: 'HTTP 403',
    egressOpen: false,
    proxies: ['HTTPS_PROXY=http://gateway:8080'],
  });

  assert.match(text, /HTTPS_PROXY=http:\/\/gateway:8080/);
  assert.match(text, /ignore ces variables/);
});

test('sans proxy déclaré, le diagnostic le dit plutôt que de rester muet', () => {
  const text = diagnosis({ message: 'HTTP 403', egressOpen: false });

  assert.match(text, /Aucun proxy déclaré/);
});

// --- Récolte déterministe ------------------------------------------------

test('deux traductions du même article ne partagent PAS un nom de fichier', () => {
  // Le piège réel : leonidaverse publie /en/news/<slug> et /fr/news/<slug>.
  // Un slug bâti sur le dernier segment en écrasait un sur deux, en silence.
  const en = harvestSlug('https://leonidaverse.com/en/news/gta-6-take-two-august-7');
  const fr = harvestSlug('https://leonidaverse.com/fr/news/gta-6-take-two-august-7');

  assert.notEqual(en, fr);
  assert.match(en, /^leonidaverse\.com__/);
});

test('le slug reste un nom de fichier sûr et borné', () => {
  const slug = harvestSlug(`https://www.gtaboom.com/${'a'.repeat(400)}?x=1#y`);

  assert.ok(slug.length <= 150);
  assert.doesNotMatch(slug, /[^a-z0-9._-]/i);
  assert.match(slug, /^gtaboom\.com__/); // le « www. » tombe, l'hôte reste lisible
});

test('la fenêtre retient les entrées récentes et jette les vieilles', () => {
  const items = [
    { link: 'a', date: '2026-08-03' },
    { link: 'b', date: '2026-08-01' },
    { link: 'c', date: '2026-07-25' },
    { link: 'd', date: null },
  ];

  const { kept } = recentEntries(items, { since: 2, today: '2026-08-03', max: 10 });

  assert.deepEqual(kept.map((i) => i.link), ['a', 'b']);
});

test('le plafond est GLOBAL et garde les plus récentes, le reste est rendu — pas jeté en silence', () => {
  const items = [
    { link: 'vieux', date: '2026-08-01' },
    { link: 'neuf', date: '2026-08-03' },
    { link: 'moyen', date: '2026-08-02' },
  ];

  const { kept, dropped } = recentEntries(items, { since: 5, today: '2026-08-03', max: 2 });

  assert.deepEqual(kept.map((i) => i.link), ['neuf', 'moyen']);
  // `dropped` alimente le compte-rendu : un plafond muet se lit comme
  // « on a tout couvert » alors qu'on a coupé.
  assert.deepEqual(dropped.map((i) => i.link), ['vieux']);
});

test('le plafond ne laisse pas l’hôte le plus bavard évincer les autres', () => {
  // Le déséquilibre réel du 15/08 : gtaboom 30 entrées, leonidaverse 2. Sous un
  // tri purement chronologique, l'hôte qui publie plus vite que la fenêtre
  // monopolise le plafond global et la récolte devient mono-source — c'est la
  // concentration qu'on mesure ensuite dans les faits (89 % d'un seul hôte).
  const items = [
    { link: 'https://www.gtaboom.com/a1', date: '2026-08-15' },
    { link: 'https://www.gtaboom.com/a2', date: '2026-08-15' },
    { link: 'https://www.gtaboom.com/a3', date: '2026-08-14' },
    { link: 'https://www.gtaboom.com/a4', date: '2026-08-14' },
    { link: 'https://leonidaverse.com/en/news/b1', date: '2026-08-13' },
    { link: 'https://leonidaverse.com/en/news/b2', date: '2026-08-13' },
  ];

  const { kept, dropped } = recentEntries(items, { since: 5, today: '2026-08-15', max: 4 });

  // Chaque hôte obtient sa part ; l'ordre RENDU reste chronologique, pour que
  // le compte-rendu se lise comme avant.
  assert.deepEqual(kept.map((i) => i.link), [
    'https://www.gtaboom.com/a1',
    'https://www.gtaboom.com/a2',
    'https://leonidaverse.com/en/news/b1',
    'https://leonidaverse.com/en/news/b2',
  ]);
  assert.deepEqual(dropped.map((i) => i.link), [
    'https://www.gtaboom.com/a3',
    'https://www.gtaboom.com/a4',
  ]);
});

test('un hôte épuisé rend ses créneaux aux autres', () => {
  // L'équité n'est pas un quota : si l'hôte minoritaire n'a qu'une entrée, elle
  // prend UN créneau et le reste du plafond revient à qui a de quoi le remplir.
  const items = [
    { link: 'https://www.gtaboom.com/a1', date: '2026-08-15' },
    { link: 'https://www.gtaboom.com/a2', date: '2026-08-14' },
    { link: 'https://www.gtaboom.com/a3', date: '2026-08-13' },
    { link: 'https://www.gtaboom.com/a4', date: '2026-08-12' },
    { link: 'https://leonidaverse.com/en/news/b1', date: '2026-08-13' },
  ];

  const { kept } = recentEntries(items, { since: 5, today: '2026-08-15', max: 4 });

  assert.deepEqual(kept.map((i) => i.link), [
    'https://www.gtaboom.com/a1',
    'https://www.gtaboom.com/a2',
    'https://www.gtaboom.com/a3',
    'https://leonidaverse.com/en/news/b1',
  ]);
});
