// Garde-fou de la contrainte IP : aucune phrase d'effet ne doit se retrouver
// telle quelle dans la source dont les faits sont tirés.
//
// Ce n'est pas une preuve d'originalité — c'est la détection du copier-coller,
// que la relecture humaine laisse justement passer parce qu'une phrase reprise
// se lit très bien. La relecture juge la langue ; ceci juge la provenance.
//
// La détection de marques est ailleurs : `check-publishable` scanne déjà les
// champs d'interface contre TRADEMARKS.

import { readFileSync } from 'node:fs';
import { effects } from './gtav-cheats-editorial.mjs';

const source = readFileSync(
  new URL('./fixtures/cheats-in-gtav.wiki', import.meta.url),
  'utf8',
).toLowerCase();

/** Une phrase courte peut coïncider par hasard (« Super Jump »). On compare des
 *  segments d'au moins six mots, seuil au-delà duquel une coïncidence n'en est
 *  plus une. */
const MIN_WORDS = 6;

function segments(text) {
  const words = text.toLowerCase().replace(/[^a-z0-9’'\s-]/g, ' ').split(/\s+/).filter(Boolean);
  const out = [];
  for (let i = 0; i + MIN_WORDS <= words.length; i++) {
    out.push(words.slice(i, i + MIN_WORDS).join(' '));
  }
  return out.length ? out : [words.join(' ')];
}

const normalizedSource = source.replace(/[^a-z0-9’'\s-]/g, ' ').replace(/\s+/g, ' ');

let problems = 0;
for (const [key, text] of Object.entries(effects)) {
  for (const [lang, value] of Object.entries(text)) {
    if (source.includes(value.toLowerCase())) {
      console.error(`REPRIS INTÉGRALEMENT  ${key}.${lang} : ${value}`);
      problems++;
      continue;
    }
    for (const segment of segments(value)) {
      if (normalizedSource.includes(segment)) {
        console.error(`SEGMENT REPRIS  ${key}.${lang} : « ${segment} »`);
        problems++;
        break;
      }
    }
  }
}

console.log(
  problems === 0
    ? `originalité : ${Object.keys(effects).length} effets, aucune reprise littérale ni segment de ${MIN_WORDS} mots`
    : `${problems} reprise(s)`,
);
process.exit(problems === 0 ? 0 : 1);
