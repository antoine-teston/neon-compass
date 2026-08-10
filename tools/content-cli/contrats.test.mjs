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
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LANGS_CIBLES } from './traduction.mjs';

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
};

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
