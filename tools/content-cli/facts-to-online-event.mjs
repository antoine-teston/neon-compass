// Transformation pure « fait d'inbox → squelette content/online-events ».
// Même partage des rôles que `facts-to-news.mjs` : aucune I/O, `cli.js` ne
// fait qu'écrire ce qu'on lui rend.
//
// Le fait d'inbox d'un événement en ligne porte le même vocabulaire qu'un fait
// `news` — `claim`, `source_url`, `source_date`, `game`, `confidence` — plus
// deux champs propres à ce kind : `starts_at` et `ends_at` (UTC complet), la
// fenêtre qui justifie le compte à rebours. Sans elle il n'y a rien à
// afficher qu'un `news` ne dirait déjà. C'est pour ça que l'identité se
// frappe avec la même mécanique que `news` (`identityKey`, `factDiscriminant`
// — gtav-poi-ids.mjs / facts-to-news.mjs), et pas une fonction réinventée ici.

import { createHash } from 'node:crypto';
import { identityKey } from '../basemap/gtav-poi-ids.mjs';
import { INBOX_SOURCE, factDiscriminant } from './facts-to-news.mjs';

/** Jeux que la veille peut désigner. Même vocabulaire que `MapGame` côté app,
 *  et même défaut que `facts-to-news.mjs` : un fait sans `game` porte sur le
 *  jeu à venir. */
const GAMES = new Set(['leonida', 'gtav']);
const DEFAULT_GAME = 'leonida';

/** Frappe un id à partir d'une clé d'identité. Sœur de `mintNewsId`
 *  (facts-to-news.mjs) : même discipline — hacher la clé, pas la recalculer à
 *  chaque lecture — préfixe différent : le schéma impose `^online_[a-z0-9_]+$`. */
export function mintOnlineEventId(key) {
  return `online_${createHash('sha256').update(key).digest('hex').slice(0, 8)}`;
}

export function factToOnlineEvent(fact) {
  if (!fact.ends_at) {
    throw new Error('ends_at manquant : sans fenêtre de fin, il n’y a pas de compte à rebours à afficher');
  }
  if (!fact.starts_at) {
    throw new Error('starts_at manquant');
  }
  if (fact.game !== undefined && !GAMES.has(fact.game)) {
    throw new Error(`jeu inconnu : ${fact.game}`);
  }

  const key = identityKey(INBOX_SOURCE, 'online-events', factDiscriminant(fact));

  return {
    id: mintOnlineEventId(key),
    game: fact.game ?? DEFAULT_GAME,
    startsAt: fact.starts_at,
    endsAt: fact.ends_at,
    // Squelette : le titre est une étiquette neutre, jamais la revendication
    // de la source — elle cite ses marques mot pour mot.
    title: { en: `Weekly update — ${fact.starts_at.slice(0, 10)}` },
    bonuses: [],
    discounts: [],
    status: 'draft',
    sources: [fact.source_url],
    confidence: fact.confidence,
    processedFrom: key,
    sourceClaim: fact.claim,
    needsRewrite: true,
  };
}
