// node --test tools/content-cli/doc.test.mjs
//
// ─────────────────────────────────────────────────────────────────────────────
// CE QUE CETTE SUITE EMPÊCHE, ET POURQUOI ELLE EXISTE
//
// La référence des fonctions de la console ÉNONCE des faits : « 29 actions »,
// « 7 fiches au carnet », la liste des noms d'actions dans ses tableaux. Rien de
// tout cela n'est calculé — c'est du texte, écrit un jour, à côté d'un code qui
// bouge.
//
// C'est très exactement la panne que `commands.mjs` a corrigée dans ce même
// dossier : une aide recopiée qui proposait `deploy-rules`, disparu depuis que
// les règles d'accès sont des politiques RLS, et qui taisait quatre commandes
// existantes. Personne ne l'avait vu parce que RIEN NE COMPARAIT LES DEUX
// LISTES.
//
// Alors on les compare. Dans les deux sens, parce qu'un seul sens ne suffit
// jamais :
//
//   - une action du code absente de la référence → elle est invisible ;
//   - une action de la référence absente du code → elle envoie taper une
//     commande qui n'existe pas, ce qui est pire.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ACTIONS } from './ui/actions.mjs';
import { CARNET } from './ui/hotfix.mjs';
import { ONGLETS } from './ui/layout.mjs';
import { EDITABLE_KINDS } from './ui/drafts.mjs';
import { enHTML, lire, rendre, sectionDe, sections, sommaire } from './doc.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
const MD = lire();

/** Les noms d'actions cités par les tableaux du CATALOGUE et du CARNET.
 *
 *  Deux restrictions, chacune apprise d'un faux positif :
 *
 *    - seulement ces deux sections. La référence a d'autres tableaux dont la
 *      première colonne est une valeur littérale — les verdicts de la Récolte
 *      (`complète`, `partielle`…), les codes HTTP. Les prendre pour des actions
 *      faisait échouer la suite sur `partielle` ;
 *    - seulement une cellule ENTIÈREMENT littérale, pour ne pas ramasser les
 *      `problemsIfPublished` et `config.toml` cités au fil de la prose. */
function actionsCitees(markdown) {
  const noms = new Set();
  const catalogue = sectionDe(markdown, 'actions')?.texte ?? '';
  const carnet = sectionDe(markdown, 'carnet')?.texte ?? '';
  for (const ligne of `${catalogue}\n${carnet}`.split('\n')) {
    // Le catalogue met l'action en première colonne, le carnet en troisième
    // (derrière le rang et le nom du geste).
    const m = ligne.match(/^\| *`([a-z][a-z0-9:-]*)` *\|/)
      ?? ligne.match(/^\| *\d+ *\|[^|]*\| *`([a-z][a-z0-9:-]*)` *\|/);
    if (m) noms.add(m[1]);
  }
  return noms;
}

// ---------------------------------------------------------------------------
// Les deux sens
// ---------------------------------------------------------------------------

test('toute action du code est citée par la référence', () => {
  const texte = MD;
  const absentes = Object.keys(ACTIONS).filter((nom) => !texte.includes(nom));
  assert.deepEqual(absentes, [], `actions absentes de la référence : ${absentes.join(', ')}`);
});

test('toute action citée par un tableau existe dans le code', () => {
  // Le sens qui aurait attrapé `deploy-rules`.
  const inventees = [...actionsCitees(MD)].filter((nom) => !(nom in ACTIONS));
  assert.deepEqual(inventees, [], `citées mais inexistantes : ${inventees.join(', ')}`);
});

test('tout geste du carnet est cité, et le carnet est complet', () => {
  const section = sectionDe(MD, 'carnet');
  assert.ok(section, 'la section du carnet a disparu de la référence');
  for (const fiche of CARNET) {
    const label = ACTIONS[fiche.action]?.label;
    assert.ok(label, `${fiche.action} : geste du carnet sans action`);
  }
  // Les sept lignes du tableau, numérotées.
  const lignes = section.texte.split('\n').filter((l) => /^\| *\d+ *\|/.test(l));
  assert.equal(
    lignes.length,
    CARNET.length,
    `le tableau du carnet a ${lignes.length} ligne(s) pour ${CARNET.length} fiche(s)`,
  );
});

// ---------------------------------------------------------------------------
// Les nombres que la référence annonce
//
// Un chiffre écrit en toutes lettres dans une doc est une affirmation. Celles-ci
// sont vérifiées, sinon elles vieillissent en silence — et un lecteur qui compte
// 31 actions là où on lui en annonce 29 cesse de faire confiance au reste.
// ---------------------------------------------------------------------------

test('le nombre d’actions annoncé est le vrai', () => {
  const n = Object.keys(ACTIONS).length;
  assert.match(MD, new RegExp(`les ${n} actions`), `la référence n’annonce pas « les ${n} actions »`);
  assert.match(MD, new RegExp(`## +3\\. Les ${n} actions`), 'le titre de la section 3 a dérivé');
});

test('le compte par groupe est le vrai', () => {
  // Le titre de chaque sous-section du catalogue porte son compte entre
  // parenthèses — y compris celui du carnet, qui renvoie à sa section mais
  // annonce quand même ses sept gestes.
  const catalogue = sectionDe(MD, 'actions').texte;
  const comptes = [...catalogue.matchAll(/^### +(.+?) \((\d+)\)$/gm)].map((m) => Number(m[2]));
  const totalAnnonce = comptes.reduce((a, b) => a + b, 0);
  const totalReel = Object.keys(ACTIONS).length;

  assert.equal(
    totalAnnonce,
    totalReel,
    `les sous-sections annoncent ${totalAnnonce} action(s) au total, le code en déclare ${totalReel}`,
  );

  // Et chaque groupe séparément, sinon deux erreurs opposées se compenseraient.
  const parGroupe = {};
  for (const a of Object.values(ACTIONS)) parGroupe[a.group] = (parGroupe[a.group] ?? 0) + 1;
  assert.equal(comptes.length, Object.keys(parGroupe).length, 'un groupe du code n’a pas sa sous-section');
  const annoncesTries = [...comptes].sort((a, b) => a - b);
  const reelsTries = Object.values(parGroupe).sort((a, b) => a - b);
  assert.deepEqual(annoncesTries, reelsTries, 'les tailles de groupes annoncées ne sont pas celles du code');
});

test('le nombre d’onglets et de kinds éditables est le vrai', () => {
  assert.match(MD, new RegExp(`les ${ONGLETS.length} onglets`, 'i'));
  for (const onglet of ONGLETS) {
    assert.ok(MD.includes(onglet.label), `onglet absent de la référence : ${onglet.label}`);
  }
  for (const kind of EDITABLE_KINDS) {
    assert.ok(MD.includes(kind), `kind éditable absent : ${kind}`);
  }
});

test('les actions marquées production le sont vraiment', () => {
  // La référence promet que « Prod » signifie destructive. Se tromper ici ferait
  // croire qu'un geste demande confirmation alors qu'il part au premier clic.
  const annoncees = new Set(
    [...MD.matchAll(/^\| *`([a-z][a-z0-9:-]*)` *\|[^|]*\| *✓ *\|/gm)].map((m) => m[1]),
  );
  for (const nom of annoncees) {
    assert.ok(
      ACTIONS[nom].destructive || ACTIONS[nom].writesRepo,
      `${nom} : coché dans une colonne qu’il ne mérite pas`,
    );
  }
});

test('toute route servie par la console est documentée', () => {
  // Le sens qui compte : une route ajoutée à `server.mjs` sans être décrite ici
  // est une fonction que personne ne saura qu'elle existe. C'est arrivé pour
  // `/api/doc` elle-même, ajoutée après la première rédaction de ce document.
  const serveur = readFileSync(join(ICI, 'ui', 'server.mjs'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
  const routes = [...serveur.matchAll(/url\.pathname === '(\/api\/[^']*)'/g)].map((m) => m[1]);
  assert.ok(routes.length >= 5, `seulement ${routes.length} route(s) trouvée(s) — le motif a dérivé`);

  const section = sectionDe(MD, 'routes');
  assert.ok(section, 'la section des routes a disparu de la référence');
  const absentes = [...new Set(routes)].filter((r) => !section.texte.includes(r));
  assert.deepEqual(absentes, [], `routes non documentées : ${absentes.join(', ')}`);
});

// ---------------------------------------------------------------------------
// Le service depuis la CLI
// ---------------------------------------------------------------------------

test('la référence se découpe en sections numérotées', () => {
  const liste = sections(MD);
  assert.ok(liste.length >= 8, `seulement ${liste.length} section(s)`);
  assert.equal(liste[0].rang, 1);
  // Le sommaire cite chaque section une fois.
  const som = sommaire(MD);
  for (const s of liste) assert.ok(som.includes(String(s.rang)), `absent du sommaire : ${s.titre}`);
});

test('une section se retrouve par son rang comme par un mot', () => {
  const parRang = sectionDe(MD, '4');
  const parMot = sectionDe(MD, 'carnet');
  assert.ok(parRang && parMot);
  assert.equal(parRang.titre, parMot.titre);
});

test('une section sans accent se retrouve quand même', () => {
  // On tape « securite », le titre porte « sécurité ».
  const s = sectionDe(MD, 'securite');
  assert.ok(s, 'la recherche insensible aux accents ne fonctionne pas');
  assert.match(s.titre, /sécurité/);
});

test('une section inconnue rend null plutôt qu’une section au hasard', () => {
  assert.equal(sectionDe(MD, 'xyzzy'), null);
  assert.equal(sectionDe(MD, ''), null);
  assert.equal(sectionDe(MD, undefined), null);
});

test('le rendu terminal retire le balisage sans manger le texte', () => {
  const rendu = rendre('## Titre\n\n| a | b |\n|---|---|\n| `deliver` | **gras** |\n');
  assert.match(rendu, /TITRE/);
  // La ligne d'alignement du tableau part…
  assert.ok(!rendu.includes('|---|'), 'la ligne d’alignement est restée');
  // …mais le contenu des cellules reste, backticks et gras retirés.
  assert.match(rendu, /deliver/);
  assert.match(rendu, /gras/);
  assert.ok(!rendu.includes('**'), 'les marqueurs de gras sont restés');
});

test('le gras qui court sur deux lignes est retiré lui aussi', () => {
  // La régression réelle : dans un paragraphe justifié, `**quoi, coûte**` tombe
  // à cheval sur deux lignes. Une substitution ligne à ligne laissait alors les
  // quatre astérisques visibles à l'écran.
  const rendu = rendre('un texte **qui porte\nde l’emphase** sur deux lignes\n');
  assert.ok(!rendu.includes('**'), `emphase non retirée : ${rendu}`);
  assert.match(rendu, /qui porte\nde l’emphase/);
});

test('la référence rendue ne contient plus aucun astérisque d’emphase', () => {
  assert.ok(!rendre(MD).includes('**'), 'des marqueurs de gras survivent au rendu');
});

test('le rendu de la référence entière ne perd aucune action', () => {
  const rendu = rendre(MD);
  const perdues = Object.keys(ACTIONS).filter((nom) => !rendu.includes(nom));
  assert.deepEqual(perdues, [], `perdues au rendu : ${perdues.join(', ')}`);
});

// ---------------------------------------------------------------------------
// Le rendu HTML, pour la console web
//
// Éprouvé sur le FICHIER RÉEL et pas seulement sur des exemples : une
// construction markdown employée un jour dans la référence et non couverte ici
// s'afficherait en texte brut au milieu du reste, sans que rien ne le dise.
// ---------------------------------------------------------------------------

test('les tableaux deviennent de vrais tableaux', () => {
  const html = enHTML('| a | b |\n|---|---|\n| 1 | 2 |\n');
  assert.match(html, /<table>/);
  assert.match(html, /<th>a<\/th>/);
  assert.match(html, /<td>1<\/td>/);
  // La ligne d'alignement ne doit pas devenir une ligne de données.
  assert.ok(!html.includes('---'), 'le séparateur est passé en contenu');
  assert.equal((html.match(/<tr>/g) ?? []).length, 2, 'une ligne de trop ou de moins');
});

test('les titres descendent d’un cran', () => {
  // La boîte de dialogue porte déjà son titre : le `#` du document devient `h2`.
  assert.match(enHTML('# Titre\n'), /<h2>Titre<\/h2>/);
  assert.match(enHTML('## Section\n'), /<h3>Section<\/h3>/);
});

test('le balisage en ligne est rendu, y compris à cheval sur deux lignes', () => {
  const html = enHTML('du `code` et **du gras\nsur deux lignes** ici\n');
  assert.match(html, /<code>code<\/code>/);
  assert.match(html, /<strong>du gras\nsur deux lignes<\/strong>/);
});

test('les listes des deux sortes sont rendues', () => {
  assert.match(enHTML('- un\n- deux\n'), /<ul>\n<li>un<\/li>\n<li>deux<\/li>\n<\/ul>/);
  assert.match(enHTML('1. un\n2. deux\n'), /<ol>\n<li>un<\/li>/);
});

test('le HTML cité dans le texte est échappé, pas interprété', () => {
  // Sans ça, un `<h2>` cité dans une phrase disparaîtrait de l’écran.
  const html = enHTML('on écrit `<h2>` dans le texte\n');
  assert.match(html, /&lt;h2&gt;/);
  assert.ok(!html.includes('<h2>dans'), 'la balise citée a été interprétée');
});

test('la référence réelle ne laisse aucun markdown non converti', () => {
  const html = enHTML(MD);
  // Le corps du texte, tables et titres retirés : il ne doit plus rester ni
  // marqueur de gras, ni ligne de séparation de tableau, ni titre en dièses.
  assert.ok(!html.includes('**'), 'des marqueurs de gras subsistent');
  assert.ok(!/\|[\s:|-]+\|/.test(html), 'une ligne d’alignement de tableau subsiste');
  assert.ok(!/^#{1,4} /m.test(html), 'un titre en dièses subsiste');
  assert.ok(!/^\| /m.test(html), 'une ligne de tableau n’a pas été convertie');
});

test('la référence réelle produit autant de tableaux qu’elle en contient', () => {
  const attendus = (MD.match(/^\|[\s:|-]+\|$/gm) ?? []).length;
  const obtenus = (enHTML(MD).match(/<table>/g) ?? []).length;
  assert.equal(obtenus, attendus, `${obtenus} tableau(x) rendus pour ${attendus} dans la source`);
});

test('le rendu HTML ne perd aucune action non plus', () => {
  const html = enHTML(MD);
  const perdues = Object.keys(ACTIONS).filter((nom) => !html.includes(nom));
  assert.deepEqual(perdues, [], `perdues au rendu HTML : ${perdues.join(', ')}`);
});
