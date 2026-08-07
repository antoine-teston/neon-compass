// node --test tools/content-cli/ui/runs.test.mjs
//
// Le verdict d'une Récolte est la chose la plus facile à croire à tort de tout
// ce dépôt. Deux pièges se cumulent :
//
//   1. `continue-on-error` fait rapporter `success` à une étape sortie en code 1
//      — au niveau de l'ÉTAPE, pas seulement du job. Vérifié le 2026-08-06 :
//      quatre runs verts, deux avaient échoué.
//   2. Le journal recopie chaque commande AVANT de l'exécuter. Le marqueur
//      « récolte déposée » est donc présent même si la commande n'a jamais
//      tourné.
//
// Un lecteur naïf déclarerait « complète » une récolte qui n'a rien fait. Ces
// tests existent pour qu'il ne puisse pas.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MARQUEURS, lignesReelles, verdictForRun, verdictFromLog } from './runs.mjs';

/** Une ligne de journal, au format que rend `gh run view --log`. */
const L = (texte) => `recolte\tUNKNOWN STEP\t2026-08-07T04:15:20.000Z ${texte}`;

/** L'écho d'une commande : cyan gras, et `gh` le rend en LITTÉRAL `^[`. */
const ECHO = (cmd) => L(`^[[36;1m${cmd}^[[0m`);

const COMPLET = [
  L('4 source(s) joignable(s) — la veille peut tourner.'),
  L('  13 page(s) rapportée(s), 2 flux lu(s)'),
  L('pas de semaine publiée — la source déclare « GTA Online event offers still active »'),
  ECHO('echo "récolte déposée sur veille/recolte ($(du -sh recolte.json) de bundle)"'),
  L('récolte déposée sur veille/recolte (176K de bundle)'),
].join('\n');

test('un journal complet rend « complète »', () => {
  const v = verdictFromLog(COMPLET);
  assert.equal(v.verdict, 'complète');
  assert.equal(v.etapes.filter((e) => e.vu).length, MARQUEURS.length);
});

test('« pas de semaine publiée » est un RÉSULTAT, pas une panne', () => {
  // La source ne publie pas toutes les semaines. Traiter son silence comme un
  // échec ferait crier au loup une fois sur deux — et on cesserait d'écouter.
  const v = verdictFromLog(COMPLET);
  const semaine = v.etapes.find((e) => e.etape.startsWith('Semaine'));
  assert.equal(semaine.vu, true);
  assert.match(semaine.resume, /aucune semaine publiée/);
});

test("l'ÉCHO d'une commande ne compte jamais comme preuve d'exécution", () => {
  // LE test de ce fichier. La commande est écrite dans le journal, mais elle a
  // échoué : le dépôt n'a pas eu lieu, et le verdict doit le dire.
  const jamaisExecute = [
    L('4 source(s) joignable(s) — la veille peut tourner.'),
    L('  13 page(s) rapportée(s), 2 flux lu(s)'),
    ECHO('echo "récolte déposée sur veille/recolte ($(du -sh recolte.json) de bundle)"'),
    L('##[error]Process completed with exit code 1.'),
  ].join('\n');

  const v = verdictFromLog(jamaisExecute);
  assert.equal(v.verdict, 'partielle');
  const depot = v.etapes.find((e) => e.etape.startsWith('Dépôt'));
  assert.equal(depot.vu, false, "l'écho de commande a été pris pour un dépôt réel");
});

test('une étape tolérante muette rend « partielle », pas « complète »', () => {
  // Le cas que l'API GitHub annonce `success` : le hub a échoué, l'étape est en
  // continue-on-error, le job est vert. Seul le journal le dit.
  const sansSemaine = COMPLET.split('\n').filter((l) => !/semaine/.test(l)).join('\n');
  const v = verdictFromLog(sansSemaine);
  assert.equal(v.verdict, 'partielle');
  assert.match(v.detail, /Semaine du mode en ligne/);
});

test('un journal vide rend « indéterminé », JAMAIS « complète »', () => {
  // Un contrôle qui, dans le doute, approuve, ne contrôle rien. C'est aussi le
  // piège d'un lecteur qui chercherait « pas d'erreur » : un journal vide n'en
  // contient aucune.
  for (const vide of ['', '   \n\n  ', null, undefined]) {
    assert.equal(verdictFromLog(vide).verdict, 'indéterminé', `« ${JSON.stringify(vide)} » mal jugé`);
  }
});

test('un journal sans le moindre marqueur rend « échec »', () => {
  const v = verdictFromLog([L('##[group]Run actions/checkout@v5'), L('##[error]boom')].join('\n'));
  assert.equal(v.verdict, 'échec');
});

test('les séquences ANSI sont retirées, dans leurs deux formes', () => {
  // `gh run view --log` rend `^[` en littéral ; un autre chemin pourrait rendre
  // l'octet ESC. Dépendre de laquelle serait dépendre d'un détail que personne
  // ne surveille chez eux.
  const litteral = L('^[[32m4 source(s) joignable(s)^[[0m');
  const octet = L('\x1b[32m4 source(s) joignable(s)\x1b[0m');
  for (const forme of [litteral, octet]) {
    assert.equal(verdictFromLog(forme).etapes[0].vu, true, `forme non nettoyée : ${JSON.stringify(forme)}`);
  }
});

test('les lignes d’écho sont retirées avant toute recherche', () => {
  const lignes = lignesReelles([ECHO('echo coucou'), L('coucou')].join('\n'));
  assert.equal(lignes.filter((l) => /coucou/.test(l)).length, 1);
});

test('le nombre de pages est remonté tel quel', () => {
  const v = verdictFromLog(COMPLET);
  assert.match(v.etapes.find((e) => e.etape === 'Récolte').resume, /13 page\(s\), 2 flux/);
});

// ---------------------------------------------------------------------------
// Le verdict d'un run entier
// ---------------------------------------------------------------------------

test('un run en cours n’est ni un succès ni un échec', () => {
  const v = verdictForRun({ status: 'in_progress', conclusion: null }, '');
  assert.equal(v.verdict, 'en cours');
});

test('un run franchement échoué reste un échec, même avec des marqueurs', () => {
  // La conclusion GitHub ne sert qu'à ça : elle ne peut pas mentir dans ce
  // sens-là. Pour tout le reste, on l'ignore au profit du journal.
  const v = verdictForRun({ status: 'completed', conclusion: 'failure' }, COMPLET);
  assert.equal(v.verdict, 'échec');
  assert.match(v.detail, /run failure/);
});

test('un run « success » avec une étape muette est rapporté partiel', () => {
  // Le cœur du problème, résumé en un test : GitHub dit vert, le journal dit
  // qu'il manque une étape, et c'est le journal qui gagne.
  const sansSemaine = COMPLET.split('\n').filter((l) => !/semaine/.test(l)).join('\n');
  const v = verdictForRun({ status: 'completed', conclusion: 'success' }, sansSemaine);
  assert.equal(v.verdict, 'partielle');
});

test('les marqueurs sont ancrés sur des chaînes réellement imprimées', () => {
  // Garde-fou contre la dérive : si un message de `fetch-source.mjs` change, ce
  // test ne le verra pas — mais il empêche au moins d'ajouter un marqueur vide
  // ou trop permissif, qui déclarerait « complète » n'importe quel journal.
  for (const m of MARQUEURS) {
    assert.ok(m.motif.source.length > 8, `${m.etape} : motif trop permissif`);
    assert.equal(m.motif.test('une ligne de journal quelconque'), false, `${m.etape} : motif trop large`);
  }
});
