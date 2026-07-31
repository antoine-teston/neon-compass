// Transformation pure « fait d'inbox → squelette content/online-events ».
// Même partage des rôles que `facts-to-news.mjs` : aucune I/O, `cli.js` ne
// fait qu'écrire ce qu'on lui rend.
//
// Le fait d'inbox d'un événement en ligne porte directement le vocabulaire du
// schéma (`game`, `startsAt`, `endsAt`, `sources`) plutôt que le
// `source_url`/`source_date` d'un fait `news` : un événement a une fenêtre à
// deux bornes, pas une seule date de publication.

import { createHash } from 'node:crypto';

/// Identité stable par hachage du CONTENU du fait, pas de sa position dans
/// l'inbox : c'est ce qui rend le run idempotent. Un fait déjà transformé se
/// réapparie sur son événement au lieu d'en créer un second.
export function identityKey(fact) {
  const material = [fact.claim, fact.game, fact.startsAt, fact.endsAt, ...(fact.sources ?? [])].join('\n');
  return createHash('sha256').update(material).digest('hex').slice(0, 16);
}

export function factToOnlineEvent(fact) {
  if (!fact.endsAt) {
    throw new Error('endsAt manquant : sans fenêtre de fin, il n’y a pas de compte à rebours à afficher');
  }
  if (!fact.startsAt) {
    throw new Error('startsAt manquant');
  }
  const key = identityKey(fact);
  return {
    id: `online_${fact.game}_${key}`,
    game: fact.game,
    startsAt: fact.startsAt,
    endsAt: fact.endsAt,
    // Squelette : le titre est une étiquette neutre, jamais la revendication
    // de la source — elle cite ses marques mot pour mot.
    title: { en: `Weekly update — ${fact.startsAt.slice(0, 10)}` },
    bonuses: [],
    discounts: [],
    status: 'draft',
    sources: fact.sources ?? [],
    confidence: fact.confidence,
    processedFrom: key,
    sourceClaim: fact.claim,
    needsRewrite: true,
  };
}
