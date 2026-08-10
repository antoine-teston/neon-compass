// Préparer une traduction, et ranger celle qu'on rend. Rien d'autre.
//
// ─────────────────────────────────────────────────────────────────────────────
// CE MODULE NE TRADUIT PAS, ET C'EST DÉLIBÉRÉ
//
// `cli.js` a longtemps porté un `translate` dont le corps disait « seul
// --dry-run est implémenté (l'appel IA reste à câbler) », pendant que
// `.claude/agents/content-editor.md` disait à l'agent « ES/IT/DE sont générés
// par le CLI — ne les remplis pas ». Chaque moitié déléguait à l'autre, et 679
// items sur 680 sont restés bilingues sans que rien ne le signale.
//
// L'appel IA n'a jamais eu à exister ici. La Routine écrit déjà `title` et
// `body` en EN et FR depuis le fait source ; écrire les cinq langues est le même
// geste, avec le même modèle, dans la même passe. Ce module lui donne les deux
// choses qu'un modèle ne fait pas bien : savoir exactement ce qui manque, et
// ranger le résultat sans rien écraser.
//
// Pur — aucune I/O. `cli.js` lit et écrit ; ici on décide.

import { UI_FIELDS } from './publishable.mjs';

/** Les langues qu'un rattrapage a le droit d'écrire.
 *
 *  `en` est la base et `fr` s'écrit à la rédaction : les laisser entrer ici
 *  ferait d'un rattrapage automatique un réécriveur de contenu rédigé. */
export const LANGS_CIBLES = Object.freeze(['es', 'it', 'de']);

const CHAMPS = new Set(UI_FIELDS);

/**
 * Ce qu'il reste à traduire, prêt à être remis à un agent.
 *
 * Rend `{ chemin: { champ: { en, fr } } }`, limité aux champs auxquels il manque
 * au moins une langue cible.
 *
 * Le `fr` accompagne le `en` parce que deux formulations lèvent une ambiguïté
 * qu'une seule laisserait : un titre d'actu tient en huit mots, et l'anglais
 * seul peut être ambigu là où le français tranche.
 *
 * `kind` et `limite` servent le même but — rendre le travail digestible par une
 * passe d'agent, plutôt que de produire les 245 ko du rattrapage complet, qu'aucun
 * contexte ne tient d'un bloc.
 */
export function travailATraduire(entries, { kind, limite } = {}) {
  const travail = {};
  for (const entry of entries) {
    if (kind && entry.kind !== kind) continue;
    if (limite && Object.keys(travail).length >= limite) break;

    const champs = {};
    for (const champ of UI_FIELDS) {
      const valeur = entry.data[champ];
      if (!valeur || typeof valeur !== 'object') continue;
      if (LANGS_CIBLES.every((l) => valeur[l])) continue;
      champs[champ] = { en: valeur.en ?? null, fr: valeur.fr ?? null };
    }
    if (Object.keys(champs).length) travail[entry.file] = champs;
  }
  return travail;
}

/**
 * Pourquoi ce lot ne peut PAS être appliqué, ou tableau vide.
 *
 * Il refuse plutôt que de deviner, et le refus qui compte le plus est le
 * dernier : écraser une valeur déjà là. Un rattrapage rejoué par mégarde
 * effacerait sinon la traduction qu'un humain vient de corriger à la main —
 * une perte silencieuse, donc la pire espèce.
 */
export function problemesDeTraduction(entries, charge, { force = false } = {}) {
  const parFichier = new Map(entries.map((e) => [e.file, e]));
  const problemes = [];

  for (const [chemin, champs] of Object.entries(charge ?? {})) {
    const entry = parFichier.get(chemin);
    if (!entry) {
      problemes.push(`${chemin} : aucun item de ce nom`);
      continue;
    }
    for (const [champ, langues] of Object.entries(champs ?? {})) {
      if (!CHAMPS.has(champ)) {
        problemes.push(`${chemin} : « ${champ} » n'est pas un champ localisé (${UI_FIELDS.join(', ')})`);
        continue;
      }
      if (!entry.data[champ] || typeof entry.data[champ] !== 'object') {
        problemes.push(`${chemin} : l'item n'a pas de champ « ${champ} » à compléter`);
        continue;
      }
      for (const [langue, texte] of Object.entries(langues ?? {})) {
        if (!LANGS_CIBLES.includes(langue)) {
          problemes.push(`${chemin} ${champ} : « ${langue} » n'est pas une langue cible (${LANGS_CIBLES.join(', ')})`);
          continue;
        }
        if (typeof texte !== 'string' || !texte.trim()) {
          problemes.push(`${chemin} ${champ} ${langue} : valeur vide ou non textuelle`);
          continue;
        }
        if (!force && entry.data[champ][langue]) {
          problemes.push(`${chemin} ${champ} ${langue} : une traduction existe déjà — --force pour l'écraser`);
        }
      }
    }
  }
  return problemes;
}

/**
 * Les fichiers à réécrire, avec leurs traductions posées.
 *
 * Ne rend QUE les items réellement touchés : réécrire les 680 fichiers pour en
 * modifier trois rendrait le diff de la PR de rattrapage illisible, et c'est
 * cette PR qu'un humain doit pouvoir relire.
 *
 * À n'appeler qu'après `problemesDeTraduction`, qui est la barrière.
 */
export function appliquer(entries, charge) {
  const parFichier = new Map(entries.map((e) => [e.file, e]));
  const ecritures = [];

  for (const [chemin, champs] of Object.entries(charge ?? {})) {
    const entry = parFichier.get(chemin);
    if (!entry) continue;

    const data = structuredClone(entry.data);
    let touche = false;
    for (const [champ, langues] of Object.entries(champs ?? {})) {
      for (const [langue, texte] of Object.entries(langues ?? {})) {
        data[champ][langue] = texte;
        touche = true;
      }
    }
    if (touche) ecritures.push({ file: chemin, data });
  }
  return ecritures;
}
