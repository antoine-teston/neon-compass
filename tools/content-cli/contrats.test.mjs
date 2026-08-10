// node --test tools/content-cli/contrats.test.mjs
//
// ─────────────────────────────────────────────────────────────────────────────
// CE QUE CETTE SUITE EMPÊCHE, ET POURQUOI ELLE EXISTE
//
// Deux fichiers de prose disent à un modèle dans quelles langues il rédige :
// `.claude/agents/content-editor.md` pour le contenu, et
// `tools/content-cli/prompts/rewrite-news.md` pour les actus de la veille.
// Aucun code ne les lit. Ce sont des instructions, pas des données — et c'est
// exactement ce qui les laisse diverger.
//
// Elles ont divergé. Le 2026-08-10, `content-editor.md` est passé aux cinq
// langues et `rewrite-news.md` a gardé « FR et EN seulement, ES/IT/DE sont
// générés plus tard par le CLI ». La Routine quotidienne ne lit QUE le second :
// le rattrapage des 680 items aurait commencé à se défaire au run suivant, sans
// qu'aucune suite ne tombe.
//
// C'est la couture d'origine reproduite un cran plus haut. La première fois,
// deux moitiés se déléguaient le travail ; la seconde, deux contrats du même
// travail ne disaient pas la même chose. Dans les deux cas la panne est la
// même : UNE RÈGLE QU'AUCUN CODE NE COMPARE N'EST PAS UNE RÈGLE.
//
// Alors on compare — au code, qui lui bouge avec des tests.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LANGS_CIBLES } from './traduction.mjs';
import { NOMS } from './commands.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));

/** Les cinq langues, dérivées du code et non recopiées : `en` est la base,
 *  `fr` s'écrit à la rédaction, et le reste est ce qu'un rattrapage a le droit
 *  d'écrire. Ajouter le chinois ici fera tomber le test du compte, ci-dessous —
 *  ce qui est le but : la prose devra suivre dans le même commit. */
const LANGUES = ['en', 'fr', ...LANGS_CIBLES];

/** Les fichiers qui disent à un modèle de RÉDIGER. `data-scout.md` n'en est pas :
 *  il extrait des faits dans la langue de la source, il ne rédige rien. */
const CONTRATS = {
  'content-editor.md': join(ICI, '..', '..', '.claude', 'agents', 'content-editor.md'),
  'rewrite-news.md': join(ICI, 'prompts', 'rewrite-news.md'),
  'routine-veille.md': join(ICI, '..', '..', '.github', 'routine-veille.md'),
};

/** Le contrat de la Routine quotidienne. Rapatrié dans le dépôt le 2026-08-10 :
 *  sa seule copie complète vivait jusque-là dans le `job_config` de la tâche
 *  planifiée, chez le fournisseur — dérivante parce qu'aucun test ne l'atteignait,
 *  et captive parce que la reconstruire ailleurs supposait d'interroger l'API dont
 *  on veut justement pouvoir se passer. */
const ROUTINE = join(ICI, '..', '..', '.github', 'routine-veille.md');

/** Ce dont la Routine dépend pour ne pas mourir à 4h17 du matin, dans une session
 *  cloud dont personne ne lira le journal. Vérifié dans les DEUX sens : un fichier
 *  déplacé la casse en silence, un fichier qu'elle cesse de citer est une étape
 *  qu'elle a perdue. */
const APPUIS = [
  '.claude/agents/data-scout.md',
  'tools/content-cli/prompts/rewrite-news.md',
  'tools/content-cli/fetch-source.mjs',
  '.github/pr-body-veille.md',
  '.github/workflows/recolte.yml',
];

const lire = (chemin) => readFileSync(chemin, 'utf8');

/** Le texte privé de ses citations.
 *
 *  Les deux contrats CITENT la règle fausse pour raconter qu'elle l'était —
 *  « ES/IT/DE sont générés par le CLI — ne les remplis pas ». Un contrat a le
 *  droit de RACONTER l'ancienne règle ; il n'a pas le droit de la PRESCRIRE.
 *  Sans cette distinction, le test ci-dessous punirait la cicatrice au lieu de
 *  la plaie, et la seule façon de le faire taire serait d'effacer la mémoire du
 *  correctif. */
const horsCitation = (texte) => texte.replace(/«[\s\S]*?»/g, ' ');

// ---------------------------------------------------------------------------
// Les deux sens
// ---------------------------------------------------------------------------

for (const [nom, chemin] of Object.entries(CONTRATS)) {
  test(`${nom} nomme les ${LANGUES.length} langues`, () => {
    const texte = lire(chemin);
    // Nommées comme des codes, entre accents graves. Chercher le mot nu serait
    // ingérable : « de » et « it » sont des mots courants du français et de
    // l'anglais, et le test passerait au vert sur n'importe quelle phrase.
    const absentes = LANGUES.filter((l) => !texte.includes(`\`${l}\``));
    assert.deepEqual(
      absentes,
      [],
      `${nom} ne nomme pas : ${absentes.join(', ')} — un modèle qui lit ce contrat n'écrira pas ces langues`,
    );
  });

  test(`${nom} ne délègue la traduction à personne`, () => {
    // Le sens qui aurait attrapé la divergence du 2026-08-10.
    const texte = horsCitation(lire(chemin));
    for (const motif of [/g[ée]n[ée]r[ée]s?[^.«»]{0,40}par le CLI/i, /ne les remplis pas/i]) {
      const trouve = texte.match(motif);
      assert.equal(
        trouve,
        null,
        `${nom} prescrit encore la délégation au CLI : « ${trouve?.[0]} » — `
          + 'or `cli.js` n\'a jamais traduit et ne traduira pas (voir traduction.mjs).',
      );
    }
  });
}

// ---------------------------------------------------------------------------
// Le contrat de la Routine, et ce sur quoi il s'appuie
// ---------------------------------------------------------------------------

test('tout fichier dont la Routine dépend existe, et elle le cite encore', () => {
  const contrat = lire(ROUTINE);
  for (const chemin of APPUIS) {
    assert.ok(
      existsSync(join(ICI, '..', '..', chemin)),
      `${chemin} : cité par le contrat de la Routine, absent du dépôt — elle mourra au prochain run`,
    );
    // Le nom de base suffit : le contrat cite `recolte.yml` sans son dossier.
    assert.ok(
      contrat.includes(chemin) || contrat.includes(chemin.split('/').pop()),
      `${chemin} : plus cité par le contrat de la Routine — une étape a disparu`,
    );
  }
});

test('toute commande du CLI citée par la Routine existe', () => {
  // La cicatrice `deploy-rules` : une aide recopiée proposait une commande
  // disparue. Ici l'enjeu est pire — personne ne lit le journal d'une session
  // cloud de 4h17, donc une commande renommée s'y perd sans un bruit.
  const citees = [...lire(ROUTINE).matchAll(/cli\.js ([a-z][a-z0-9-]*)/g)].map((m) => m[1]);
  assert.ok(citees.length >= 3, `seulement ${citees.length} commande(s) trouvée(s) — le motif a dérivé`);
  const inventees = [...new Set(citees)].filter((nom) => !NOMS.includes(nom));
  assert.deepEqual(inventees, [], `citées par la Routine mais inexistantes : ${inventees.join(', ')}`);
});

test('la branche roulante est resynchronisée sur main', () => {
  // Trouvé le 2026-08-10 au soir, une heure avant le run suivant : `veille/courante`
  // traînait sur origin avec 81 commits de retard, et l'étape 1 s'y plaçait sans
  // rien y ramener. La Routine aurait donc exécuté le `cli.js` et le
  // `rewrite-news.md` d'avant les correctifs du jour — doublons recréés,
  // traductions retombées à deux langues — en ayant l'air de bien fonctionner.
  const contrat = lire(ROUTINE);
  assert.match(contrat, /git merge origin\/main/,
    'l’étape 1 ne ramène plus `main` dans la branche roulante : elle exécutera le code du jour où la branche est née');
  // Et la raison, sans quoi la ligne finira retirée comme une redondance.
  assert.match(contrat, /retard/,
    'la raison du merge a disparu de l’étape 1 — quelqu’un retirera la ligne');
});

test('les interdits irréversibles ne dépendent pas d’un fichier lu', () => {
  // L'amorçage hébergé les répète, et le contrat le justifie. Si cette
  // justification disparaît, quelqu'un finira par « simplifier » l'amorçage en
  // les retirant — or ils doivent tenir même quand la lecture du contrat échoue.
  const contrat = lire(ROUTINE);
  assert.match(contrat, /ne doit pas dépendre[\s\S]{0,80}lecture réussie/i,
    'la raison d’être des interdits répétés dans l’amorçage a disparu du contrat');
  for (const interdit of [/ne publies JAMAIS/, /ne fusionnes JAMAIS/, /jamais sur `main`/]) {
    assert.match(contrat, interdit, `interdit absent de l’amorçage cité : ${interdit}`);
  }
});

test('« les cinq langues » en est bien cinq', () => {
  // Un nombre écrit en toutes lettres dans une consigne est une affirmation.
  // Le jour où le chinois entre dans LANGS_CIBLES, ce test tombe et force la
  // prose à suivre — au lieu de laisser deux contrats annoncer « cinq » à un
  // modèle qui en a six à écrire.
  assert.equal(LANGUES.length, 5, 'LANGS_CIBLES a bougé : les contrats disent encore « cinq »');
  for (const [nom, chemin] of Object.entries(CONTRATS)) {
    assert.match(lire(chemin), /cinq/i, `${nom} n'annonce plus son compte de langues`);
  }
});
