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

/** Même socle qu'`invalidReason` côté news (facts-to-news.mjs) : ces deux
 *  constantes n'y sont pas exportées (`ISO_DATE`, `CONFIDENCES` restent
 *  privées à ce fichier-là), donc on les reprend ici à l'identique plutôt que
 *  d'élargir la surface publique de facts-to-news.mjs pour ça — même choix
 *  déjà fait pour `GAMES`/`DEFAULT_GAME` juste au-dessus. */
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const CONFIDENCES = new Set(['confirmed-official', 'multi-source', 'single-source', 'rumor']);

/** Frappe un id à partir d'une clé d'identité. Sœur de `mintNewsId`
 *  (facts-to-news.mjs) : même discipline — hacher la clé, pas la recalculer à
 *  chaque lecture — préfixe différent : le schéma impose `^online_[a-z0-9_]+$`. */
export function mintOnlineEventId(key) {
  return `online_${createHash('sha256').update(key).digest('hex').slice(0, 8)}`;
}

export function factToOnlineEvent(fact) {
  // Même socle qu'un fait `news` avant même de parler de fenêtre : sans ça,
  // un fait mal formé traverserait la matérialisation par lot et n'échouerait
  // qu'au `validate` suivant, noyé parmi les entrées saines de la semaine.
  if (!fact.claim) {
    throw new Error('fait sans claim');
  }
  if (!fact.source_url) {
    throw new Error('fait sans source_url — un événement en ligne doit pouvoir être remonté à sa source');
  }
  if (!ISO_DATE.test(fact.source_date ?? '')) {
    throw new Error(`date de source malformée : ${fact.source_date} (attendu AAAA-MM-JJ)`);
  }
  if (!CONFIDENCES.has(fact.confidence)) {
    throw new Error(`confiance inconnue : ${fact.confidence}`);
  }
  if (fact.game !== undefined && !GAMES.has(fact.game)) {
    throw new Error(`jeu inconnu : ${fact.game}`);
  }
  if (!fact.ends_at) {
    throw new Error('ends_at manquant : sans fenêtre de fin, il n’y a pas de compte à rebours à afficher');
  }
  if (!fact.starts_at) {
    throw new Error('starts_at manquant');
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

/**
 * Matérialisation par lot — sœur de `materializeNews` (facts-to-news.mjs),
 * même discipline : filtrage par kind, idempotence par `processedFrom`, un
 * conflit bloque le lot ENTIER (un run à moitié appliqué laisserait l'inbox à
 * moitié marquée, et le fait fautif reviendrait au run suivant sans qu'on
 * sache ce qui a déjà été fait).
 *
 * Différence avec `materializeNews` : là-bas, validation et construction du
 * squelette sont inlinées dans la boucle, faute d'une fonction par-fait à
 * réutiliser. Ici, `factToOnlineEvent` existe déjà et porte les deux (elle
 * calcule la même clé, frappe le même id) — le lot se contente de l'appeler
 * et de gérer ce qu'elle seule ne peut pas savoir : que ce fait ait déjà été
 * matérialisé par un run précédent, ou qu'il collisionne avec un id existant
 * porté par un autre `processedFrom`.
 *
 * @param facts     faits d'inbox, tous kinds confondus, aplatis depuis les
 *                  fichiers `.facts.json`
 * @param existing  [{ path, data }] — les fichiers actuels de
 *                  content/online-events
 * @returns {{
 *   writes: Array<{path: string, data: object}>,        squelettes à écrire
 *   alreadyMaterialized: Array<{key: string, id: string}>, déjà couverts
 *   covered: Array<{fact: object, key: string, id: string}>, à marquer dans l'inbox
 *   skipped: Array<{claim: string, reason: string}>,    écartés, mais classés
 *   conflicts: Array<{claim: string, reason: string}>   si non vide, N'ÉCRIRE RIEN
 * }}
 */
export function materializeOnlineEvents(facts, existing) {
  const byID = new Map(existing.map((entry) => [entry.data.id, entry]));
  const byProcessedFrom = new Map(
    existing.filter((entry) => entry.data.processedFrom).map((entry) => [entry.data.processedFrom, entry]),
  );

  const writes = [];
  const alreadyMaterialized = [];
  const covered = [];
  const skipped = [];
  const conflicts = [];

  for (const fact of facts) {
    if (fact.kind !== 'online-event') {
      skipped.push({ claim: fact.claim, reason: `kind « ${fact.kind} » — pas un événement en ligne` });
      continue;
    }

    let data;
    try {
      data = factToOnlineEvent(fact);
    } catch (err) {
      conflicts.push({ claim: fact.claim, reason: err.message });
      continue;
    }

    const { processedFrom: key, id } = data;

    // Déjà matérialisé — par un run précédent, ou par un fait plus haut dans
    // CE lot. On se réapparie, on n'écrit pas un second item. L'item déjà
    // rédigé n'est pas touché : la rédaction est une décision humaine, la
    // matérialisation ne l'écrase jamais.
    const previous = byProcessedFrom.get(key);
    if (previous) {
      alreadyMaterialized.push({ key, id: previous.data.id });
      covered.push({ fact, key, id: previous.data.id });
      continue;
    }

    if (byID.has(id)) {
      conflicts.push({ claim: fact.claim, reason: `l'id frappé ${id} existe déjà avec un autre processedFrom` });
      continue;
    }

    const entry = { path: `content/online-events/${id}.json`, data };

    writes.push(entry);
    // Tenir les deux index à jour au fil du lot : sans ça, deux faits
    // identiques du même run produiraient deux fichiers de même id sans que
    // rien ne le signale.
    byID.set(id, entry);
    byProcessedFrom.set(key, entry);
    covered.push({ fact, key, id });
  }

  // Un conflit invalide le lot entier : matérialiser la moitié d'un run
  // laisserait l'inbox à moitié marquée, et le fait fautif reviendrait au run
  // suivant sans qu'on sache ce qui a déjà été fait.
  if (conflicts.length) {
    return { writes: [], alreadyMaterialized: [], covered: [], skipped: [], conflicts };
  }

  return { writes, alreadyMaterialized, covered, skipped, conflicts };
}
