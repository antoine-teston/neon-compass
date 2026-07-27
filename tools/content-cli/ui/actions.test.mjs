// node --test tools/content-cli/ui/actions.test.mjs
//
// Ces tests portent sur la surface d'attaque de la console web, pas sur son
// ergonomie : un serveur local qui lance des processus doit être incapable
// d'exécuter autre chose que ce qui est listé.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ACTIONS, ID_PATTERN, resolveAction } from './actions.mjs';

test('aucun argv ne contient de métacaractère de shell', () => {
  // `spawn` est appelé sans `shell: true`, donc ceci ne serait pas exploitable —
  // mais un argv qui en contient signalerait qu'on a commencé à construire des
  // commandes par concaténation, ce qui est le début du problème.
  for (const [name, action] of Object.entries(ACTIONS)) {
    for (const arg of action.argv) {
      assert.doesNotMatch(arg, /[;&|`$><\n]/, `${name} : argv suspect « ${arg} »`);
    }
  }
});

test('une action inconnue est refusée', () => {
  assert.throws(() => resolveAction('rm-rf'), /action inconnue/);
  assert.throws(() => resolveAction(''), /action inconnue/);
  assert.throws(() => resolveAction(undefined), /action inconnue/);
});

test('les identifiants hors motif sont refusés', () => {
  const hostiles = [
    'abc; rm -rf /',
    '../../etc/passwd',
    'a b',
    '$(whoami)',
    '`id`',
    'a'.repeat(129),
    '',
  ];
  for (const id of hostiles) {
    assert.throws(() => resolveAction('moderate:approve', { id }), /exige un identifiant|refusé/, `accepté : ${id}`);
  }
});

test('un identifiant Firestore normal est accepté et passé en argv distinct', () => {
  const { argv } = resolveAction('moderate:approve', { id: 'aB3_x-9' });
  assert.deepEqual(argv, ['cli.js', 'moderate:approve', 'aB3_x-9']);
});

test('une action sans identifiant en refuse un', () => {
  // Empêche qu'un client bricolé glisse un argument à une commande qui n'en
  // attend pas.
  assert.throws(() => resolveAction('release', { id: 'x' }), /n'accepte pas d'identifiant/);
});

test('resolveAction ne partage pas le tableau argv de la déclaration', () => {
  // Sans la copie, chaque appel pousserait un identifiant de plus dans la
  // constante — la deuxième modération enverrait deux ids.
  resolveAction('moderate:approve', { id: 'un' });
  const { argv } = resolveAction('moderate:approve', { id: 'deux' });
  assert.deepEqual(argv, ['cli.js', 'moderate:approve', 'deux']);
  assert.equal(ACTIONS['moderate:approve'].argv.length, 2);
});

test('toute action de production est marquée destructive ou needsCredentials', () => {
  // Le serveur refuse une action destructive sans confirmation ET sans
  // credentials ; ce test garantit qu'une action du groupe `prod` ne peut pas
  // échapper aux deux.
  for (const [name, action] of Object.entries(ACTIONS)) {
    if (action.group !== 'prod' && action.group !== 'moderation') continue;
    assert.ok(action.destructive || action.needsCredentials, `${name} n'exige rien`);
  }
});

test('les groupes déclarés sont ceux que la page sait afficher', () => {
  const known = new Set(['checks', 'local', 'prod', 'moderation']);
  for (const [name, action] of Object.entries(ACTIONS)) {
    assert.ok(known.has(action.group), `${name} : groupe « ${action.group} » sans conteneur dans index.html`);
  }
});

test('ID_PATTERN reste ancré des deux côtés', () => {
  assert.ok(ID_PATTERN.source.startsWith('^') && ID_PATTERN.source.endsWith('$'));
  assert.equal(ID_PATTERN.test('ok\nrm -rf /'), false);
});
