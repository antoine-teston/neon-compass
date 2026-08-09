// node --test tools/content-cli/ui/page.test.mjs
//
// ─────────────────────────────────────────────────────────────────────────────
// LE CÂBLAGE ENTRE LA PAGE ET SON SCRIPT
//
// `console.js` réclame 35 éléments par identifiant. Aucun test ne comparait ces
// deux listes — et la panne qu'un écart produit est la pire de sa catégorie :
// `getElementById` rend `null`, `null.onclick = …` lève dans un module, le
// module s'arrête là, et **les branchements qui suivaient ne sont jamais
// posés**. Un bouton sans effet, aucun message, et l'erreur seulement dans la
// console du navigateur — que personne n'ouvre pour cliquer sur « Récolte ».
//
// Une lettre de trop dans un identifiant suffit. C'est exactement le genre de
// faute qu'une relecture ne voit pas et qu'un test voit toujours.
//
// Volontairement du texte, pas un DOM : monter jsdom pour cette question serait
// une dépendance de plus dans un dépôt qui n'en veut pas, pour vérifier une
// correspondance entre deux chaînes.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ICI = dirname(fileURLToPath(import.meta.url));
const HTML = readFileSync(join(ICI, 'index.html'), 'utf8');
const JS = readFileSync(join(ICI, 'console.js'), 'utf8');

/** Les identifiants que le script réclame. */
function demandes(source) {
  return [...source.matchAll(/getElementById\('([^']+)'\)/g)].map((m) => m[1]);
}

/** Les identifiants que la page pose. */
function poses(html) {
  return new Set([...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]));
}

test('tout élément réclamé par le script existe dans la page', () => {
  const existants = poses(HTML);
  const absents = [...new Set(demandes(JS))].filter((id) => !existants.has(id));
  assert.deepEqual(
    absents,
    [],
    `réclamés par console.js, absents de index.html : ${absents.join(', ')}`,
  );
});

test('aucun identifiant n’est posé deux fois dans la page', () => {
  // Deux éléments du même identifiant : `getElementById` en rend UN, toujours le
  // premier, et l'autre reste muet sans que rien ne le dise.
  const tous = [...HTML.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]);
  const vus = new Set();
  const doubles = tous.filter((id) => (vus.has(id) ? true : (vus.add(id), false)));
  assert.deepEqual(doubles, [], `identifiants en double : ${[...new Set(doubles)].join(', ')}`);
});

// ---------------------------------------------------------------------------
// La boîte de la référence
// ---------------------------------------------------------------------------

test('la référence a son bouton, sa boîte et sa fermeture', () => {
  for (const id of ['reference', 'reference-ouvrir', 'ref-close', 'ref-texte', 'ref-sommaire']) {
    assert.ok(poses(HTML).has(id), `absent de la page : ${id}`);
  }
  assert.match(JS, /fetch\('\/api\/doc'\)/, 'la page ne demande pas la référence au serveur');
});

test('la boîte de la référence ne redéclare pas de `display`', () => {
  // Le piège documenté dans `index.html` le 2026-08-08 : une règle d'AUTEUR qui
  // impose un `display` à un `<dialog>` l'emporte sur la feuille du navigateur,
  // et la boîte reste à l'écran une fois fermée — voire avant toute ouverture.
  // Le style de `#reference` porte donc sur son CORPS, jamais sur elle-même.
  const regleDuDialogue = HTML.match(/#reference\s*\{[^}]*\}/);
  if (regleDuDialogue) {
    assert.ok(
      !/display\s*:/.test(regleDuDialogue[0]),
      '#reference impose un display — la fermeture ne fonctionnera pas',
    );
  }
  // Et la règle qui rétablit la fermeture doit toujours être là, pour tous.
  assert.match(HTML, /dialog:not\(\[open\]\)\s*\{\s*display:\s*none/);
});
