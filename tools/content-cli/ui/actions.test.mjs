// node --test tools/content-cli/ui/actions.test.mjs
//
// Ces tests portent sur la surface d'attaque de la console web, pas sur son
// ergonomie : un serveur local qui lance des processus doit être incapable
// d'exécuter autre chose que ce qui est listé.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ACTIONS, ID_PATTERN, resolveAction } from './actions.mjs';
import { CARNET, FICHES } from './hotfix.mjs';

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
    if (!['prod', 'moderation'].includes(action.group)) continue;
    assert.ok(action.destructive || action.needsCredentials, `${name} n'exige rien`);
  }
});

/** Les groupes qui ne passent PAS par `renderActions`, et par où ils passent.
 *
 *  Une liste explicite plutôt qu'un fourre-tout : ajouter un groupe ici est une
 *  décision qu'on écrit, pas un oubli qu'on tolère. */
const RENDUS_AILLEURS = {
  hotfix: 'le carnet (renderCarnet)',
  github: 'la section Récolte (renderRecolte)',
};

test('les groupes déclarés sont ceux que la page sait afficher', () => {
  // Ce test lisait une liste écrite à la main tout en affirmant, dans son
  // message d'échec, vérifier `index.html`. Il ne le faisait pas. Corrigé le
  // 2026-08-08 : il lit maintenant les DEUX fichiers, donc il attrape le cas
  // réel — un groupe déclaré dont la boucle de rendu ou le conteneur manque, et
  // dont les boutons n'apparaîtraient nulle part, sans erreur ni avertissement.
  const ici = dirname(fileURLToPath(import.meta.url));
  const page = readFileSync(join(ici, 'index.html'), 'utf8');
  const script = readFileSync(join(ici, 'console.js'), 'utf8');

  const boucle = /for \(const group of \[([^\]]+)\]\)/.exec(script);
  assert.ok(boucle, 'la boucle de rendu des groupes est introuvable dans console.js');
  const rendus = new Set([...boucle[1].matchAll(/'([a-z-]+)'/g)].map((m) => m[1]));
  assert.ok(rendus.size >= 4, `boucle de rendu suspecte : ${[...rendus]}`);

  for (const groupe of rendus) {
    assert.ok(
      page.includes(`id="g-${groupe}"`),
      `console.js rend le groupe « ${groupe} », mais index.html n'a pas de #g-${groupe}`,
    );
  }
  for (const [name, action] of Object.entries(ACTIONS)) {
    const ok = rendus.has(action.group) || action.group in RENDUS_AILLEURS;
    assert.ok(ok, `${name} : groupe « ${action.group} » rendu nulle part`);
  }
});

// ---------------------------------------------------------------------------
// Champs typés — la généralisation de `needsID`
// ---------------------------------------------------------------------------

test('un paramètre déclaré part dans son propre élément d’argv', () => {
  const { argv, bin } = resolveAction('recolte', { since: '7', max: '30' });
  assert.equal(bin, 'gh');
  assert.deepEqual(argv, ['workflow', 'run', 'recolte.yml', '--ref', 'main', '-f', 'since=7', '-f', 'max=30']);
});

test('les défauts déclarés s’appliquent quand le champ est absent', () => {
  const { argv } = resolveAction('recolte');
  assert.ok(argv.includes('since=2') && argv.includes('max=15'), argv.join(' '));
});

test('un paramètre hors motif est refusé', () => {
  // Le cas qui compte : `spawn` est appelé sans shell, donc ceci ne serait pas
  // exploitable — mais un paramètre qui échappe à son motif signifie que le
  // motif ne sert plus à rien, et c'est le début du problème.
  const hostiles = ['2; rm -rf /', '$(id)', '`whoami`', '2 --ref evil', '9999', 'deux', '2\n--ref=evil'];
  for (const since of hostiles) {
    assert.throws(
      () => resolveAction('recolte', { since }),
      /refusé/,
      `accepté : ${JSON.stringify(since)}`,
    );
  }
});

test('un champ vidé retombe sur son défaut, qui est une constante', () => {
  // Comportement délibéré, pas un trou : l'utilisateur qui efface la case veut
  // le défaut, et ce défaut est écrit dans la déclaration — il ne vient pas de
  // la requête. Un paramètre REQUIS, lui, lève (test suivant).
  const { argv } = resolveAction('recolte', { since: '', max: '' });
  assert.ok(argv.includes('since=2') && argv.includes('max=15'), argv.join(' '));
  assert.throws(() => resolveAction('deploy-function', { name: '' }), /exige le paramètre/);
});

test('un paramètre NON DÉCLARÉ est refusé, jamais ignoré', () => {
  // La différence est tout sauf cosmétique. Ignorer en silence laisserait
  // croire qu'un champ a été pris en compte alors qu'il ne l'est pas — et la
  // prochaine personne à lire le code chercherait où il agit.
  assert.throws(() => resolveAction('recolte', { ref: 'evil' }), /n'accepte pas le paramètre/);
  assert.throws(() => resolveAction('recolte', { '--ref': 'evil' }), /n'accepte pas le paramètre/);
  assert.throws(() => resolveAction('migrations-apply', { since: '2' }), /n'accepte pas le paramètre/);
});

test('un paramètre requis manquant est une erreur', () => {
  assert.throws(() => resolveAction('deploy-function'), /exige le paramètre/);
  assert.throws(() => resolveAction('content-source'), /exige le paramètre/);
});

test('contentBaseURL refuse http, et n’accepte que https ou off', () => {
  // Un `contentBaseURL` en clair ferait servir tout le contenu en HTTP à tous
  // les clients, sans mise à jour de l'app pour le rattraper.
  assert.throws(() => resolveAction('content-source', { url: 'http://exemple.test' }), /refusé/);
  assert.throws(() => resolveAction('content-source', { url: 'javascript:alert(1)' }), /refusé/);
  assert.doesNotThrow(() => resolveAction('content-source', { url: 'off' }));
  assert.doesNotThrow(() => resolveAction('content-source', { url: 'https://cdn.exemple.test/v1' }));
});

test('un nom de fonction hors motif est refusé', () => {
  for (const name of ['../../etc', 'a b', 'Majuscule', 'nom;rm', '']) {
    assert.throws(() => resolveAction('deploy-function', { name }), /refusé|exige/, `accepté : ${name}`);
  }
  assert.doesNotThrow(() => resolveAction('deploy-function', { name: 'rebuild-community-bundles' }));
});

test('resolveAction ne partage pas l’argv des actions à paramètres', () => {
  resolveAction('recolte', { since: '1' });
  const { argv } = resolveAction('recolte', { since: '3' });
  assert.equal(argv.filter((a) => a.startsWith('since=')).length, 1, argv.join(' '));
  assert.equal(ACTIONS.recolte.argv.length, 5);
});

test('seules les actions déclarées portent un binaire, et il ne vient jamais de la requête', () => {
  // `bin` est lu dans la DÉCLARATION. Si un jour il devenait lisible depuis le
  // corps de la requête, ce test ne le verrait pas — mais `resolveAction` ne
  // reçoit que des paramètres déclarés, et `bin` n'en est pas un.
  assert.throws(() => resolveAction('validate', { bin: '/bin/sh' }), /n'accepte pas le paramètre/);
  assert.equal(resolveAction('validate').bin, null);
});

// ---------------------------------------------------------------------------
// Le carnet de hotfix
// ---------------------------------------------------------------------------

test('toute fiche du carnet désigne une action qui existe', () => {
  for (const fiche of CARNET) {
    assert.ok(ACTIONS[fiche.action], `fiche « ${fiche.action} » sans action correspondante`);
  }
});

test('tout geste du groupe hotfix a sa fiche', () => {
  // Un bouton correctif sans fiche est un bouton qu'on presse sans savoir ce
  // qu'il coûte. La page ne l'afficherait pas ; ce test évite d'en écrire un.
  for (const [name, action] of Object.entries(ACTIONS)) {
    if (action.group !== 'hotfix') continue;
    assert.ok(FICHES[name], `${name} est dans le carnet sans fiche`);
  }
});

test('aucune fiche ne laisse le retour arrière vide', () => {
  // La règle du carnet : « sans objet, l'opération est idempotente » est une
  // réponse ; « je ne sais pas » n'en est pas une, et un champ vide non plus.
  for (const fiche of CARNET) {
    for (const champ of ['quoi', 'cout', 'verification', 'retour']) {
      assert.ok(fiche[champ]?.trim().length > 3, `${fiche.action} : champ « ${champ} » vide`);
    }
  }
});

test('les gestes qui écrivent en production sont marqués destructive', () => {
  const lecturesSeules = new Set(['migrations-dry']);
  for (const fiche of CARNET) {
    if (lecturesSeules.has(fiche.action)) continue;
    assert.ok(ACTIONS[fiche.action].destructive, `${fiche.action} écrit sans être destructive`);
  }
});

test('ID_PATTERN reste ancré des deux côtés', () => {
  assert.ok(ID_PATTERN.source.startsWith('^') && ID_PATTERN.source.endsWith('$'));
  assert.equal(ID_PATTERN.test('ok\nrm -rf /'), false);
});

// ---------------------------------------------------------------------------
// Le piège du <dialog> à qui on impose un `display`
//
// La feuille du navigateur ferme un `<dialog>` avec
// `dialog:not([open]) { display: none }`. Une règle d'AUTEUR l'emporte sur celle
// du navigateur quelle que soit sa spécificité : poser `display: flex` sur
// `dialog` annule donc la fermeture. « Fermer » met bien `open` à faux, et la
// boîte reste à l'écran — visible même avant la première ouverture.
//
// Régression introduite puis corrigée le 2026-08-08, en passant l'éditeur en
// colonne flex pour réparer son défilement. Le CSS n'a pas de suite de tests
// dans ce dépôt ; celui-ci lit la feuille et vérifie la seule règle dont
// l'absence transforme un correctif en panne.
// ---------------------------------------------------------------------------

/** Le texte sans ses commentaires CSS et HTML.
 *
 *  Indispensable, et la première version de ce test l'avait oublié — pour la
 *  DEUXIÈME fois dans ce dépôt, après `tools/monitor/imports.test.mjs`. Le
 *  commentaire qui EXPLIQUE la règle la cite, donc un test qui cherche la règle
 *  dans le texte brut est satisfait par sa propre documentation : retirer la
 *  ligne de code ne le faisait pas broncher.
 *
 *  Un contrôle qu'une explication suffit à contenter ne contrôle rien. */
function sansCommentaires(texte) {
  return texte.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/<!--[\s\S]*?-->/g, ' ');
}

test('un `display` imposé à un <dialog> s’accompagne de sa fermeture', () => {
  const page = sansCommentaires(
    readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'index.html'), 'utf8'),
  );

  // Le bloc `dialog { … }` de premier niveau, hors `::backdrop` et hors `:not`.
  const bloc = /(^|\})\s*dialog\s*\{([^}]*)\}/m.exec(page);
  assert.ok(bloc, 'aucune règle `dialog { … }` trouvée dans index.html');

  if (/display\s*:/.test(bloc[2])) {
    assert.match(
      page,
      /dialog:not\(\[open\]\)\s*\{[^}]*display\s*:\s*none/,
      'index.html impose un `display` à `dialog` sans rétablir '
      + '`dialog:not([open]) { display: none }` — la boîte restera à l’écran après « Fermer »',
    );
  }
});

test('le geste irréversible n’est pas là où on clique pour fermer', () => {
  // « Écarter » a d'abord été posé juste avant « Fermer », donc exactement à la
  // place que « Fermer » occupait la veille. La mémoire du doigt fait le reste.
  // Il vit maintenant AVANT le message, qui l'écarte des trois autres.
  const page = sansCommentaires(
    readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'index.html'), 'utf8'),
  );
  const pied = /<div class="editor-foot">([\s\S]*?)<\/div>/.exec(page);
  assert.ok(pied, 'pied de l’éditeur introuvable');

  const ordre = [...pied[1].matchAll(/id="(ed-[a-z]+)"/g)].map((m) => m[1]);
  assert.equal(ordre[0], 'ed-delete', `« Écarter » n’est plus en tête du pied : ${ordre}`);
  assert.ok(
    ordre.indexOf('ed-msg') < ordre.indexOf('ed-close'),
    `le message doit séparer « Écarter » de « Fermer » : ${ordre}`,
  );
});
