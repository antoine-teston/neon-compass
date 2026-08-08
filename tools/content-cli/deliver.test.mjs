// node --test tools/content-cli/deliver.test.mjs
//
// Ce qui est testé ici est la COMPOSITION : titre, corps et nom de branche sont
// dérivés du diff, jamais saisis. C'est ce qui permet à la console de livrer
// sans qu'aucun texte libre n'atteigne une ligne de commande — et accessoirement
// ce qui rend le message plus juste qu'un message écrit à la main.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { changementsDe, corpsDe, nomDeBranche, resteDeCote, titreDe, transitionDe } from './deliver.mjs';

test('les fichiers de contenu sont reconnus, les autres écartés', () => {
  const porcelain = [
    ' M content/news/news_abc123.json',
    '?? content/online-events/online_9f.json',
    ' M tools/content-cli/cli.js',
    ' M content/inbox/2026-08-07-veille.facts.json',
    ' M content/schema/news.schema.json',
    ' M README.md',
    '',
  ].join('\n');

  const c = changementsDe(porcelain);
  assert.deepEqual(c.map((x) => x.id), ['news_abc123', 'online_9f']);
  assert.deepEqual(c.map((x) => x.kind), ['news', 'online-events']);
});

test('l’inbox est écartée — c’est de la matière première, pas du contenu', () => {
  // Et surtout : elle contient du TEXTE DE TIERS. L'emporter dans une livraison
  // la commiterait, ce que la contrainte IP du projet interdit.
  assert.deepEqual(changementsDe(' M content/inbox/faits.json'), []);
});

test('un chemin qui ne ressemble pas à un item est ignoré', () => {
  const hostiles = [
    ' M content/news/../../etc/passwd',
    ' M content/news/sous/dossier.json',
    ' M content/news/pas-du-json.txt',
    ' M content/cdn-versions.json',
    'XY',
    '',
  ].join('\n');
  assert.deepEqual(changementsDe(hostiles), []);
});

test('un fichier neuf est distingué d’un fichier modifié', () => {
  const c = changementsDe([' M content/news/a.json', '?? content/news/b.json', 'A  content/news/c.json'].join('\n'));
  assert.deepEqual(c.map((x) => x.neuf), [false, true, true]);
});

test('changementsDe supporte une entrée vide ou absente', () => {
  for (const rien of ['', null, undefined, '\n\n']) {
    assert.deepEqual(changementsDe(rien), [], JSON.stringify(rien));
  }
});

test('la transition de statut est ce qu’un relecteur veut voir', () => {
  assert.equal(transitionDe({ status: 'draft' }, { status: 'published' }), 'draft → published');
  assert.equal(transitionDe({ status: 'draft' }, { status: 'draft' }), 'reste draft');
  assert.equal(transitionDe(null, { status: 'draft' }), 'créé draft');
  // `(null, null)` disait « modifié » jusqu'au 2026-08-08, et ça ne disait rien :
  // ce cas veut dire que le fichier EXISTE et ne se parse pas. Depuis que
  // l'absence a son propre signal (`undefined`), `null` n'est plus ambigu du
  // côté local, et « illisible » est ce qu'un relecteur a besoin de lire.
  assert.equal(transitionDe(null, null), 'illisible');
});

test('le titre annonce le nombre, par kind', () => {
  const c = changementsDe([
    ' M content/news/a.json',
    ' M content/news/b.json',
    ' M content/online-events/c.json',
  ].join('\n'));
  assert.equal(titreDe(c), 'content(livraison): 2 news, 1 online-events');
});

test('le corps AVERTIT quand le merge publiera tout seul', () => {
  // C'est le point le plus important de ce fichier. Pour l'actu et les
  // événements en ligne, approuver la PR vaut mise en ligne : le relecteur doit
  // le savoir avant de cliquer, pas après.
  const corps = corpsDe(changementsDe(' M content/news/a.json'));
  assert.match(corps, /Le merge de cette PR PUBLIE/);
  assert.match(corps, /dernier garde-fou/);
});

test('le corps prévient qu’un kind manuel fait TOUT refuser', () => {
  // Le garde-fou de périmètre de `publish-news` est global : un merge qui touche
  // un POI ne publie rien du tout, actu comprise. Le découvrir après coup coûte
  // une journée de fraîcheur.
  const corps = corpsDe(changementsDe([' M content/news/a.json', ' M content/poi/b.json'].join('\n')));
  assert.match(corps, /fait refuser `publish-news` en entier|refuser `publish-news`/);
  assert.match(corps, /Livrer séparément/);
});

test('un lot purement manuel n’annonce pas de publication automatique', () => {
  const corps = corpsDe(changementsDe(' M content/poi/a.json'));
  assert.doesNotMatch(corps, /Le merge de cette PR PUBLIE/);
});

test('le corps liste chaque item avec sa transition', () => {
  const c = changementsDe(' M content/news/news_abc.json');
  const corps = corpsDe(c, { 'content/news/news_abc.json': 'draft → published' });
  assert.match(corps, /\| `news_abc` \| news \| draft → published \|/);
});

test('le nom de branche évite les collisions du même jour', () => {
  assert.equal(nomDeBranche('2026-08-07', []), 'content/livraison-2026-08-07');
  assert.equal(nomDeBranche('2026-08-07', ['content/livraison-2026-08-07']), 'content/livraison-2026-08-07-2');
  assert.equal(
    nomDeBranche('2026-08-07', ['content/livraison-2026-08-07', 'content/livraison-2026-08-07-2']),
    'content/livraison-2026-08-07-3',
  );
});

test('importer le module ne déclenche AUCUNE commande git', () => {
  // Le garde-fou qui rend ces tests sûrs : `main()` ne tourne que si le script
  // est lancé en ligne de commande. Sans ce test, une régression sur cette
  // condition ferait brancher et pousser le dépôt à chaque `node --test`.
  const source = readFileSync(new URL('./deliver.mjs', import.meta.url), 'utf8');
  assert.match(source, /process\.argv\[1\][\s\S]{0,80}endsWith\('deliver\.mjs'\)/);
});

import { readFileSync } from 'node:fs';

test('une ligne dont l’espace de tête a été mangée reste lisible', () => {
  // La régression du 2026-08-07 : `git()` faisait `.trim()` sur la sortie de
  // `git status --porcelain`, ce qui supprimait la colonne d'état d'un fichier
  // seulement modifié (` M chemin`). Les colonnes glissaient d'un cran, plus
  // rien ne correspondait, et la livraison annonçait « rien à livrer » avec des
  // fichiers modifiés sous les yeux. La cause est corrigée dans `git()` ; ce
  // test verrouille la tolérance du parseur, pour que la panne ne puisse pas
  // revenir en silence par un autre chemin.
  assert.deepEqual(changementsDe('M content/news/a.json').map((c) => c.id), ['a']);
  assert.deepEqual(changementsDe(' M content/news/a.json').map((c) => c.id), ['a']);
  assert.deepEqual(changementsDe('?? content/news/a.json').map((c) => c.id), ['a']);
  assert.deepEqual(changementsDe('content/news/a.json').map((c) => c.id), ['a']);
});

// ---------------------------------------------------------------------------
// Ce que la livraison n'emporte PAS
//
// Corrigé le 2026-08-08. `main()` ne demandait à git que l'état de `content/` :
// une modification de code en attente restait dans l'arbre de travail sans
// qu'une seule ligne le dise, et on ouvrait une PR en croyant l'arbre propre.
// Mentir par omission, dans le geste le plus conséquent de la console.
// ---------------------------------------------------------------------------

test('ce qui part n’est pas re-annoncé comme laissé de côté', () => {
  // La confusion la plus facile à introduire : un fichier annoncé livré ET
  // laissé, ce qui rendrait les deux listes inutiles.
  const { laisse } = resteDeCote(' M content/news/a.json\n M tools/content-cli/cli.js');
  assert.deepEqual(laisse, ['tools/content-cli/cli.js']);
});

test('l’inbox est distinguée d’un oubli', () => {
  // Son absence est une RÈGLE tenue — du texte tiers, jamais commité — pas une
  // distraction. Les mélanger apprendrait à ignorer l'avertissement.
  const r = resteDeCote('?? content/inbox/2026-08-08.facts.json\n M Scripts/db-test.sh');
  assert.deepEqual(r.exclu, ['content/inbox/2026-08-08.facts.json']);
  assert.deepEqual(r.laisse, ['Scripts/db-test.sh']);
});

test('les deux colonnes d’état sont retirées, l’espace de tête comprise', () => {
  // Sans ça le chemin vaut « M tools/… », que plus aucun motif ne reconnaît —
  // et un fichier de contenu se retrouverait annoncé comme laissé de côté.
  assert.deepEqual(resteDeCote(' M tools/a.mjs').laisse, ['tools/a.mjs']);
  assert.deepEqual(resteDeCote('MM tools/a.mjs').laisse, ['tools/a.mjs']);
  assert.deepEqual(resteDeCote('?? tools/monitor/').laisse, ['tools/monitor/']);
  // Et la tolérance à une ligne dont l'espace de tête a été mangée, comme pour
  // `changementsDe` — la panne du 2026-08-07 ne doit pas revenir par ce chemin.
  assert.deepEqual(resteDeCote('M tools/a.mjs').laisse, ['tools/a.mjs']);
});

test('un renommage est rangé sous sa destination', () => {
  assert.deepEqual(resteDeCote('R  vieux.mjs -> neuf.mjs').laisse, ['neuf.mjs']);
});

test('resteDeCote supporte une entrée vide ou absente', () => {
  assert.deepEqual(resteDeCote(''), { exclu: [], laisse: [] });
  assert.deepEqual(resteDeCote(null), { exclu: [], laisse: [] });
});

test('un fichier écarté ne s’affiche pas « draft → null »', () => {
  // Constaté le 2026-08-08 en écartant un brouillon depuis la console : la
  // Livraison annonçait `draft → null`. Un `null` de JavaScript dans une
  // étiquette lue par un humain est toujours un oubli.
  assert.equal(transitionDe({ status: 'draft' }, undefined), 'écarté (était draft)');
  assert.equal(transitionDe(null, undefined), 'écarté');
});

test('« écarté » et « illisible » ne se confondent pas', () => {
  // Le fichier n'existe plus VS il existe et ne se parse pas : un geste
  // délibéré d'un côté, une panne de l'autre. Les afficher pareil ferait passer
  // un JSON cassé pour une suppression voulue.
  assert.equal(transitionDe({ status: 'published' }, undefined), 'écarté (était published)');
  assert.equal(transitionDe({ status: 'published' }, null), 'published → illisible');
  assert.equal(transitionDe(null, null), 'illisible');
});
