// node --test tools/content-cli/commands.test.mjs
//
// Le test qui compte est le premier : la déclaration et le `switch` de `cli.js`
// doivent lister EXACTEMENT les mêmes commandes.
//
// Sans lui, on retombe dans ce qu'on vient de corriger : la ligne d'usage
// proposait `deploy-rules`, disparu depuis que les règles d'accès sont des
// politiques RLS, et taisait `bundle`, `check-seeds`, `release` et `deploy-cdn`.
// Personne ne l'avait vu parce que rien ne comparait les deux listes.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { COMMANDES, GROUPES, NOMS, aide, aideDe, distance, suggestion } from './commands.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));

/** Les `case '<nom>':` du switch de `cli.js`, commentaires retirés.
 *
 *  Retirés parce qu'un commentaire qui CITE une commande satisfait un test qui
 *  la cherche dans le texte brut — piège rencontré deux fois dans ce dépôt le
 *  2026-08-08, dans `imports.test.mjs` puis dans `actions.test.mjs`. */
function casDuSwitch() {
  const source = readFileSync(join(ICI, 'cli.js'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
  return new Set([...source.matchAll(/^\s*case '([a-z:-]+)':/gm)].map((m) => m[1]));
}

test('toute commande déclarée a un traitement', () => {
  const cas = casDuSwitch();
  // `news` et `help` sont traités AVANT le switch — ils ne chargent pas
  // `content/`, justement pour rester utilisables quand un fichier est cassé.
  const horsSwitch = new Set(['news']);
  const orphelines = NOMS.filter((n) => !cas.has(n) && !horsSwitch.has(n));
  assert.deepEqual(orphelines, [], `déclarées sans traitement : ${orphelines.join(', ')}`);
});

test('tout traitement est déclaré', () => {
  const cas = [...casDuSwitch()];
  const muettes = cas.filter((c) => !NOMS.includes(c));
  assert.deepEqual(muettes, [], `traitées sans être dans l’aide : ${muettes.join(', ')}`);
});

test('aucune commande n’est rangée dans un groupe inexistant', () => {
  const groupes = new Set(GROUPES.map(([g]) => g));
  for (const c of COMMANDES) {
    assert.ok(groupes.has(c.groupe), `${c.nom} : groupe inconnu « ${c.groupe} »`);
  }
});

test('aucun doublon dans les noms', () => {
  assert.equal(new Set(NOMS).size, NOMS.length);
});

test('chaque commande dit ce qu’elle fait, en une phrase', () => {
  for (const c of COMMANDES) {
    assert.ok(c.resume?.length > 10, `${c.nom} : résumé trop court`);
    assert.ok(c.resume.endsWith('.'), `${c.nom} : le résumé n’est pas une phrase`);
    assert.ok(c.resume.length < 90, `${c.nom} : résumé de ${c.resume.length} car., il déborde`);
  }
});

// ---------------------------------------------------------------------------
// L'aide rendue
// ---------------------------------------------------------------------------

test('l’aide liste TOUTES les commandes', () => {
  const texte = aide();
  for (const nom of NOMS) assert.ok(texte.includes(nom), `absent de l’aide : ${nom}`);
  for (const [groupe] of GROUPES) assert.ok(texte.includes(groupe.toUpperCase()), groupe);
});

test('l’aide ne propose rien qui n’existe pas', () => {
  // Le symptôme exact de la panne d'origine : `deploy-rules` dans l'usage.
  assert.ok(!aide().includes('deploy-rules'));
});

test('le détail d’une commande porte sa forme et ses pièges', () => {
  const detail = aideDe('news');
  assert.match(detail, /--since/);
  assert.match(detail, /publishedAt/);
  assert.match(detail, /Exemples/);
  assert.equal(aideDe('nexiste-pas'), null);
});

// ---------------------------------------------------------------------------
// La faute de frappe
// ---------------------------------------------------------------------------

test('une faute d’une lettre est rattrapée', () => {
  assert.equal(suggestion('new'), 'news');
  assert.equal(suggestion('chek-seeds'), 'check-seeds');
  assert.equal(suggestion('validat'), 'validate');
  assert.equal(suggestion('pull-nws'), 'pull-news');
});

test('un mot sans rapport ne déclenche PAS de suggestion', () => {
  // Proposer « news » à qui tape « deploy » enverrait sur une fausse piste, ce
  // qui coûte plus cher que de ne rien proposer.
  assert.equal(suggestion('xyzzy'), null);
  assert.equal(suggestion(''), null);
});

test('la distance d’édition est celle qu’on croit', () => {
  assert.equal(distance('news', 'news'), 0);
  assert.equal(distance('new', 'news'), 1);
  assert.equal(distance('', 'news'), 4);
});
