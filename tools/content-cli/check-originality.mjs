// Garde-fou de la contrainte IP : aucune phrase rédigée ne doit se retrouver
// telle quelle dans la source dont elle est tirée.
//
// Ce n'est pas une preuve d'originalité — c'est la détection du copier-coller,
// que la relecture humaine laisse justement passer parce qu'une phrase reprise
// se lit très bien. La relecture juge la langue ; ceci juge la provenance.
//
// Deux corpus, un même algorithme :
//  - les cheats comparent leurs effets à LA fixture du wiki — un seul corpus
//    partagé par tous les codes, aucune source individuelle par entrée ;
//  - les événements en ligne comparent leurs champs rédigés à LEUR PROPRE
//    `sourceClaim` — le fait brut que `facts-to-online-event.mjs` conserve
//    pour la relecture (une liste de remises nomme des véhicules et des
//    commerces : rien de ce qui s'affiche ne doit passer sans ce contrôle).
//    `sourceClaim` lui-même n'est JAMAIS comparé : il a le droit de citer ses
//    sources mot pour mot, marques comprises, puisqu'il n'est jamais affiché
//    (`check-publishable` ne le scanne pas non plus).
//
// La détection de marques déposées est ailleurs : `check-publishable` scanne
// déjà les champs d'interface contre TRADEMARKS.

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { effects } from './gtav-cheats-editorial.mjs';
import {
  notANominativeName,
  nominativeFieldsFor,
  nominativeListFieldsFor,
  redactedListFieldsFor,
} from './nominative-fields.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CONTENT = join(HERE, '..', '..', 'content');

/** Une phrase courte peut coïncider par hasard (« Super Jump »). On compare des
 *  segments d'au moins six mots, seuil au-delà duquel une coïncidence n'en est
 *  plus une. */
const MIN_WORDS = 6;

function normalize(text) {
  return text.toLowerCase().replace(/[^a-z0-9’'\s-]/g, ' ').replace(/\s+/g, ' ').trim();
}

function segments(text) {
  const words = normalize(text).split(/\s+/).filter(Boolean);
  const out = [];
  for (let i = 0; i + MIN_WORDS <= words.length; i++) {
    out.push(words.slice(i, i + MIN_WORDS).join(' '));
  }
  return out.length ? out : [words.join(' ')];
}

/** @returns la description d'une reprise, ou `null` si `value` est original
 *  par rapport à `source`. */
function reused(source, value) {
  if (source.toLowerCase().includes(value.toLowerCase())) {
    return `REPRIS INTÉGRALEMENT : ${value}`;
  }
  const normalizedSource = normalize(source);
  for (const segment of segments(value)) {
    if (normalizedSource.includes(segment)) {
      return `SEGMENT REPRIS : « ${segment} »`;
    }
  }
  return null;
}

let problems = 0;

// --- Cheats : comparés à la fixture du wiki (un seul corpus partagé) -------
const cheatsSource = readFileSync(new URL('./fixtures/cheats-in-gtav.wiki', import.meta.url), 'utf8');
let cheatsChecked = 0;
for (const [key, text] of Object.entries(effects)) {
  for (const [lang, value] of Object.entries(text)) {
    cheatsChecked++;
    const problem = reused(cheatsSource, value);
    if (problem) {
      console.error(`CHEAT  ${key}.${lang} : ${problem}`);
      problems++;
    }
  }
}

// --- Événements en ligne : chaque entrée comparée à SON PROPRE sourceClaim -
//
// Deux familles de champs, deux contrôles — parce qu'un NOM n'est pas une
// RÉDACTION. `bonuses[].activity` vaut « Fleeca Heist Finale » : le nom d'une
// activité du jeu, référence factuelle au même titre qu'un nom de POI, et il
// figure forcément dans la prose de la source dont il est tiré. Le passer au
// contrôle de reprise le ferait échouer sur une donnée parfaitement légitime,
// et la seule façon de le faire passer serait de déformer le nom — donc de
// mentir.
//
// La liste de ces champs et la contrainte qui les accompagne — RESTER un nom —
// vivent dans `nominative-fields.mjs`, partagées avec `check-publishable`, qui
// s'appuie sur la même notion pour accorder son exception aux marques.
//
// Les champs rédigés, eux, restent comparés à la prose source. Ce sont les
// seuls que quelqu'un pourrait être tenté de recopier.
const REDACTED_FIELDS = ['title'];

function* localizedTexts(localized) {
  if (!localized) return;
  for (const [lang, value] of Object.entries(localized)) {
    if (typeof value === 'string') yield [lang, value];
  }
}

const onlineEventsDir = join(CONTENT, 'online-events');
const onlineEventFiles = existsSync(onlineEventsDir)
  ? readdirSync(onlineEventsDir).filter((f) => f.endsWith('.json'))
  : [];

let onlineEventsChecked = 0;
for (const file of onlineEventFiles) {
  const data = JSON.parse(readFileSync(join(onlineEventsDir, file), 'utf8'));
  if (!data.sourceClaim) continue; // squelette sans fait conservé : rien à quoi comparer

  const check = (label, value) => {
    onlineEventsChecked++;
    const problem = reused(data.sourceClaim, value);
    if (problem) {
      console.error(`${file}  ${label} : ${problem}`);
      problems++;
    }
  };

  const checkName = (label, value) => {
    onlineEventsChecked++;
    const problem = notANominativeName(value);
    if (problem) {
      console.error(`${file}  ${label} : ${problem}`);
      problems++;
    }
  };

  for (const field of REDACTED_FIELDS) {
    for (const [lang, value] of localizedTexts(data[field])) check(`${field}.${lang}`, value);
  }
  for (const [listField, textField] of redactedListFieldsFor('online-events')) {
    (data[listField] ?? []).forEach((item, index) => {
      for (const [lang, value] of localizedTexts(item[textField])) check(`${listField}[${index}].${textField}.${lang}`, value);
    });
  }
  for (const field of nominativeFieldsFor('online-events')) {
    for (const [lang, value] of localizedTexts(data[field])) checkName(`${field}.${lang}`, value);
  }
  for (const [listField, textField] of nominativeListFieldsFor('online-events')) {
    (data[listField] ?? []).forEach((item, index) => {
      for (const [lang, value] of localizedTexts(item[textField])) checkName(`${listField}[${index}].${textField}.${lang}`, value);
    });
  }
}

console.log(
  problems === 0
    ? `originalité : ${cheatsChecked} effet(s) de cheat, ${onlineEventsChecked} champ(s) d'événement en ligne — ` +
      `aucune reprise littérale ni segment de ${MIN_WORDS} mots dans les champs rédigés, aucun nom qui soit une phrase ni une marque nue`
    : `${problems} reprise(s)`,
);
process.exit(problems === 0 ? 0 : 1);
