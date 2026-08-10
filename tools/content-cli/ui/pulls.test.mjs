// node --test tools/content-cli/ui/pulls.test.mjs
//
// Le test qui compte est celui de la dérive : `pulls.mjs` recopie en JS une
// règle qui vit en shell dans `content.yml`. Deux copies d'une même règle, c'est
// la panne `deploy-rules` — celle qui a valu à ce dossier son `commands.mjs`.
// Personne ne l'avait vue parce que rien ne comparait les deux listes.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  MOTIF_PUBLIABLES,
  MOTIF_TOLERES,
  effetDuMerge,
  phraseDeLEffet,
  refusDeFusion,
  verdictDePublication,
  verdictDesControles,
  vueDeLaPR,
} from './pulls.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
const WORKFLOW = readFileSync(join(ICI, '..', '..', '..', '.github', 'workflows', 'content.yml'), 'utf8');

// ---------------------------------------------------------------------------
// La dérive contre le workflow
// ---------------------------------------------------------------------------

test('les motifs de périmètre sont ceux du workflow', () => {
  // Les deux `grep` de l'étape « Le merge reste-t-il dans le périmètre ».
  const tolere = WORKFLOW.match(/grep -vE '([^']+)'/);
  const publiable = WORKFLOW.match(/grep -E '([^']+)'/);
  assert.ok(tolere, 'le grep de tolérance a disparu du workflow — la règle a bougé');
  assert.ok(publiable, 'le grep de publication a disparu du workflow');

  // Le shell écrit `\.json`, JS aussi une fois la chaîne échappée : on compare
  // les motifs tels qu'ils seront compilés, pas leur graphie.
  assert.equal(
    new RegExp(MOTIF_TOLERES).source,
    new RegExp(tolere[1]).source,
    'MOTIF_TOLERES a dérivé du workflow',
  );
  assert.equal(
    new RegExp(MOTIF_PUBLIABLES).source,
    new RegExp(publiable[1]).source,
    'MOTIF_PUBLIABLES a dérivé du workflow',
  );
});

test('aucune étape tolérante n’est apparue dans content.yml', () => {
  // `verdictDesControles` fait confiance au statut de la CI, et c'est LÉGITIME
  // seulement tant que ce workflow n'a pas d'étape en `continue-on-error` —
  // l'API rapporte alors `success` pour une étape sortie en 1 (voir runs.mjs).
  // Rien dans le JS ne rendrait cette hypothèse visible : c'est ici qu'elle vit.
  assert.ok(
    !/continue-on-error/.test(WORKFLOW),
    'content.yml a gagné une étape tolérante — le statut de la CI ne peut plus servir de garde, '
    + 'il faut relire le journal comme le fait runs.mjs pour la Récolte',
  );
});

// ---------------------------------------------------------------------------
// L'effet du merge
// ---------------------------------------------------------------------------

const cas = [
  { quoi: 'une actu seule', fichiers: ['content/news/a.json'], attendu: 'publie' },
  { quoi: 'un événement en ligne', fichiers: ['content/online-events/e.json'], attendu: 'publie' },
  {
    quoi: 'actu + verrou de versions',
    fichiers: ['content/news/a.json', 'content/cdn-versions.json'],
    attendu: 'publie',
  },
  {
    quoi: 'actu + inbox',
    fichiers: ['content/news/a.json', 'content/inbox/faits.json'],
    attendu: 'publie',
  },
  {
    quoi: 'actu + POI dans le même lot',
    fichiers: ['content/news/a.json', 'content/poi/p.json'],
    attendu: 'hors-perimetre',
  },
  { quoi: 'un POI seul', fichiers: ['content/poi/p.json'], attendu: 'sans-effet' },
  { quoi: 'du code seul', fichiers: ['tools/content-cli/cli.js'], attendu: 'sans-effet' },
  {
    quoi: 'du code ET une actu',
    fichiers: ['tools/content-cli/cli.js', 'content/news/a.json'],
    attendu: 'publie',
  },
  { quoi: 'rien', fichiers: [], attendu: 'sans-effet' },
];

for (const { quoi, fichiers, attendu } of cas) {
  test(`effet du merge — ${quoi} → ${attendu}`, () => {
    assert.equal(effetDuMerge(fichiers).verdict, attendu);
  });
}

test('le code hors content/ ne compte jamais dans le périmètre', () => {
  // Le workflow ne regarde que `content/` : un fichier Swift ne fait pas sortir
  // du périmètre. C'est contre-intuitif et ça mérite son test.
  const e = effetDuMerge(['NeonCompass/App/AppModel.swift', 'content/news/a.json']);
  assert.equal(e.verdict, 'publie');
  assert.deepEqual(e.hors, []);
});

test('la phrase dit un nombre, jamais une couleur seule', () => {
  const publie = phraseDeLEffet(effetDuMerge(['content/news/a.json', 'content/news/b.json']));
  assert.match(publie, /PUBLIE 2/);
  const melange = phraseDeLEffet(effetDuMerge(['content/news/a.json', 'content/poi/p.json']));
  assert.match(melange, /ne publiera RIEN/);
  assert.match(phraseDeLEffet(effetDuMerge([])), /ne publie rien/);
});

// ---------------------------------------------------------------------------
// Les contrôles
// ---------------------------------------------------------------------------

test('le verdict des contrôles distingue vert, rouge, en cours et inconnu', () => {
  assert.equal(verdictDesControles([{ status: 'COMPLETED', conclusion: 'SUCCESS' }]).etat, 'vert');
  assert.equal(verdictDesControles([{ status: 'COMPLETED', conclusion: 'FAILURE', name: 'check' }]).etat, 'rouge');
  assert.equal(verdictDesControles([{ status: 'IN_PROGRESS' }]).etat, 'en cours');
  assert.equal(verdictDesControles([]).etat, 'inconnu');
  assert.equal(verdictDesControles(null).etat, 'inconnu');
});

test('un contrôle sauté ne vaut pas un échec', () => {
  // `content.yml` saute des jobs selon l'événement : les compter comme rouges
  // interdirait toute fusion.
  const v = verdictDesControles([
    { status: 'COMPLETED', conclusion: 'SKIPPED' },
    { status: 'COMPLETED', conclusion: 'SUCCESS' },
  ]);
  assert.equal(v.etat, 'vert');
});

// ---------------------------------------------------------------------------
// Le refus, qui est la barrière
// ---------------------------------------------------------------------------

const prVerte = (fichiers) => ({
  files: fichiers.map((path) => ({ path })),
  statusCheckRollup: [{ status: 'COMPLETED', conclusion: 'SUCCESS' }],
});

test('une PR de contenu à CI verte est fusionnable', () => {
  assert.equal(refusDeFusion(prVerte(['content/news/a.json'])), null);
});

test('une PR qui touche du code est refusée, et le dit', () => {
  const refus = refusDeFusion(prVerte(['content/news/a.json', 'tools/content-cli/cli.js']));
  assert.equal(refus.code, 422);
  assert.match(refus.message, /hors de content\//);
  assert.match(refus.message, /cli\.js/, 'le refus doit NOMMER le fichier fautif');
});

test('une PR à CI rouge est refusée', () => {
  const refus = refusDeFusion({
    files: [{ path: 'content/news/a.json' }],
    statusCheckRollup: [{ status: 'COMPLETED', conclusion: 'FAILURE', name: 'check' }],
  });
  assert.equal(refus.code, 412);
  assert.match(refus.message, /rouge/);
});

test('une PR dont la CI tourne encore est refusée', () => {
  const refus = refusDeFusion({
    files: [{ path: 'content/news/a.json' }],
    statusCheckRollup: [{ status: 'IN_PROGRESS' }],
  });
  assert.equal(refus.code, 412);
  assert.match(refus.message, /en cours/);
});

test('une PR sans contrôle du tout est refusée', () => {
  // `inconnu` n'est pas `vert`. Dans le doute on ne fusionne pas.
  const refus = refusDeFusion({ files: [{ path: 'content/news/a.json' }], statusCheckRollup: [] });
  assert.equal(refus.code, 412);
});

test('une PR absente et une PR vide sont refusées', () => {
  assert.equal(refusDeFusion(null).code, 404);
  assert.equal(refusDeFusion(prVerte([])).code, 422);
});

// ---------------------------------------------------------------------------
// La couture entre les deux formes
//
// `refusDeFusion` lit la forme BRUTE de `gh` (`files`, `statusCheckRollup`).
// `pullRequestsOuvertes` rend une forme PUBLIQUE (`nbFichiers`, `controles`,
// `refus`) qui ne porte NI l'un NI l'autre. Passer la seconde à la première,
// c'est ce que faisait `server.mjs` : `pr.files` valait `undefined`, donc zéro
// fichier, donc « cette PR ne change aucun fichier » sur une PR de huit ajouts.
// Aucune PR n'était fusionnable depuis la console.
//
// Rien ne l'a vu parce que tous les tests ci-dessus construisent la forme brute
// à la main. C'est la couture, et non chaque bout, qui manquait de test.
// ---------------------------------------------------------------------------

test('la vue publique porte le refus calculé sur les données brutes', () => {
  const vue = vueDeLaPR({ number: 83, title: 'Veille', ...prVerte(['content/news/a.json']) });
  assert.equal(vue.refus, null, 'une PR de contenu à CI verte est fusionnable');
  assert.equal(vue.nbFichiers, 1);
  assert.equal(vue.controles.etat, 'vert');
});

test('la vue publique ne se fait jamais juger « sans fichier »', () => {
  // La régression exacte. Le message importe autant que le refus : « ne change
  // aucun fichier » envoie chercher une PR vide qui n'existe pas.
  const refus = refusDeFusion(vueDeLaPR(prVerte(['content/news/a.json'])));
  assert.doesNotMatch(
    refus?.message ?? '',
    /ne change aucun fichier/,
    'une forme injugeable ne doit pas être maquillée en PR vide',
  );
  assert.equal(refus.code, 500, 'une forme qu’on ne sait pas juger est une panne, pas un verdict');
});

test('« aucun fichier » reste réservé à une PR réellement vide', () => {
  // Le pendant du test précédent : le garde-fou ne doit pas avaler le vrai cas.
  const refus = refusDeFusion(prVerte([]));
  assert.equal(refus.code, 422);
  assert.match(refus.message, /ne change aucun fichier/);
});

// ---------------------------------------------------------------------------
// Le verdict de publication
// ---------------------------------------------------------------------------

test('le journal distingue les quatre issues', () => {
  assert.equal(verdictDePublication('publish: 42 objet(s) téléversé(s) dans le bucket cdn').verdict, 'publié');
  assert.equal(verdictDePublication('### Publication automatique : non').verdict, 'rien à publier');
  assert.equal(verdictDePublication('Ce merge sort du périmètre de la veille :').verdict, 'hors périmètre');
  assert.equal(verdictDePublication('### Publication automatique : impossible').verdict, 'identifiants absents');
});

test('« identifiants absents » l’emporte sur un job vert', () => {
  // Le cas qui justifie de lire le journal : le job RESTE VERT et n'a rien
  // publié. Un `✔` naïf dirait « publié » à un contenu resté sur `main`.
  const log = 'Tout va bien\n### Publication automatique : impossible\nSUPABASE_URL manque';
  assert.equal(verdictDePublication(log).verdict, 'identifiants absents');
});

test('le nombre d’objets téléversés est repris tel quel', () => {
  assert.match(verdictDePublication('publish: 7 objet(s) téléversé(s)').detail, /^7 objet/);
});

test('un journal muet est « indéterminé », jamais un succès', () => {
  assert.equal(verdictDePublication('').verdict, 'indéterminé');
  assert.equal(verdictDePublication('   ').verdict, 'indéterminé');
  assert.equal(verdictDePublication('des lignes sans rapport').verdict, 'indéterminé');
});
