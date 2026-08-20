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

// Le filtre de pertinence, ajouté le 2026-08-19 avec les deux premières sources
// GÉNÉRALISTES du registre. Sans lui, ces hôtes cassent la récolte au lieu de
// l'élargir : leur densité d'articles sur le jeu est d'environ 1 sur 10 (mesuré
// sur le flux de VGC), et `recentEntries` remplissant le plafond À TOUR DE RÔLE
// par hôte, neuf articles hors sujet par généraliste ÉVINCENT les articles utiles
// de gtaboom. Le plafond est partagé : ce qu'un hôte prend, un autre le perd.
test('un article hors sujet d’un hôte généraliste est écarté', () => {
  const { kept, dropped } = recentEntries(
    [
      { title: 'Tekken 8 game director joins SNK', link: 'https://www.videogameschronicle.com/news/tekken', date: '2026-08-18' },
      { title: 'GTA 6 gameplay allegedly leaks', link: 'https://www.videogameschronicle.com/news/leak', date: '2026-08-18' },
    ],
    { since: 2, today: '2026-08-19', max: 15 },
  );

  assert.deepEqual(kept.map((i) => i.link), ['https://www.videogameschronicle.com/news/leak']);
  assert.equal(dropped.length, 1);
  assert.match(dropped[0].raison ?? String(dropped[0].reason ?? ''), /hors sujet/i);
});

test('le même article hors sujet d’un hôte dédié est GARDÉ', () => {
  // La dissymétrie est le cœur du filtre : gtaboom ne parle que de cette
  // franchise, donc un titre qui ne nomme pas la marque y est quand même
  // pertinent (« Everything we know about the map »). Filtrer là ferait perdre
  // de vrais articles — le filtre suit le registre, pas le texte seul.
  const { kept, dropped } = recentEntries(
    [{ title: 'Everything we know about the map', link: 'https://www.gtaboom.com/map', date: '2026-08-18' }],
    { since: 2, today: '2026-08-19', max: 15 },
  );

  assert.equal(kept.length, 1);
  assert.deepEqual(dropped, []);
});

test('le filtre lit aussi l’URL, pas seulement le titre', () => {
  // Un titre peut nommer le jeu sans la marque (« Everything we know about
  // Vice City's map ») ; le slug d'URL la porte presque toujours.
  const { kept } = recentEntries(
    [{ title: 'Everything we know about the next open world', link: 'https://insider-gaming.com/gta-6-map-details', date: '2026-08-18' }],
    { since: 2, today: '2026-08-19', max: 15 },
  );

  assert.equal(kept.length, 1);
});

test('le filtre s’applique AVANT le plafond, donc il ne gaspille pas de créneau', () => {
  // Le piège qu'il faut éviter : filtrer après la sélection à tour de rôle
  // laisserait un généraliste consommer ses créneaux avec du hors-sujet, puis
  // les rendre vides. Deux articles utiles doivent survivre à un plafond de 2
  // même noyés dans du bruit.
  const items = [
    { title: 'Hors sujet A', link: 'https://www.videogameschronicle.com/a', date: '2026-08-18' },
    { title: 'Hors sujet B', link: 'https://www.videogameschronicle.com/b', date: '2026-08-18' },
    { title: 'GTA 6 delayed', link: 'https://www.videogameschronicle.com/c', date: '2026-08-18' },
    { title: 'Rockstar hires', link: 'https://insider-gaming.com/d', date: '2026-08-18' },
  ];
  const { kept } = recentEntries(items, { since: 2, today: '2026-08-19', max: 2 });

  assert.equal(kept.length, 2);
  assert.deepEqual(
    kept.map((i) => i.link).sort(),
    ['https://insider-gaming.com/d', 'https://www.videogameschronicle.com/c'],
  );
});
