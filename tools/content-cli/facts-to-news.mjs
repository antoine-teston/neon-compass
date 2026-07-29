// Transformation pure « fait d'inbox → squelette content/news ». Aucune I/O,
// aucun Firestore : tout ce qui décide vit ici, et `cli.js` ne fait qu'écrire ce
// qu'on lui rend — même partage des rôles que `draft-to-poi.mjs`.
//
// Ce module existe pour une raison précise : la rédaction d'un item d'actu est
// le seul maillon de la chaîne qu'une machine ne peut pas faire seule (il faut
// reformuler un fait sans jamais reprendre une marque déposée). Tout le reste —
// identité, idempotence, garde-fous — doit donc être du code vérifiable, sinon
// le run hebdomadaire n'est pas automatisable : il dépendrait du jugement d'un
// modèle pour savoir ce qu'il a déjà publié.

import { createHash } from 'node:crypto';
import { identityKey } from '../basemap/gtav-poi-ids.mjs';

/** Source d'identité des items nés de la veille — partie stable de la clé
 *  écrite dans `processedFrom`, et ce sur quoi le run suivant se réapparie. */
export const INBOX_SOURCE = 'inbox';

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
/** Doit rester le contrat exact de `data-scout` (.claude/agents/data-scout.md).
 *  Une valeur qu'il émet mais qu'on ne connaît pas ici devient un conflit — et
 *  un conflit bloque le lot ENTIER. Un seul fait `single-source` suffirait donc
 *  à faire perdre toute la veille de la semaine, en silence. */
const CONFIDENCES = new Set(['confirmed-official', 'multi-source', 'single-source', 'rumor']);

/** Catégorie par défaut du squelette. La rédaction peut la corriger : c'est une
 *  décision éditoriale (une date de sortie n'est pas un événement daté), pas
 *  quelque chose qui se déduit du fait brut. */
const DEFAULT_CATEGORY = 'announcement';

/** Texte posé en attendant la rédaction. Volontairement PAS le fait brut : le
 *  fait cite ses sources mot pour mot, marques déposées comprises, et
 *  `check-publishable` scanne title/body de toutes les entrées — publiées ou
 *  non. Recopier le fait ferait échouer la CI dès la matérialisation. Le fait
 *  est conservé dans `sourceClaim`, qui n'est jamais affiché. */
const PLACEHOLDER = {
  title: { fr: 'À rédiger', en: 'To be written' },
  body: { fr: 'À rédiger depuis le fait source.', en: 'To be written from the source fact.' },
};

/** Discriminant d'un fait : son contenu, pas son emplacement. Un fait
 *  re-signalé la semaine suivante — dans un autre fichier d'inbox, à un autre
 *  rang — doit se réapparier sur l'item qu'il a déjà produit, sinon le fil
 *  accumule des doublons à chaque run. */
export function factDiscriminant(fact) {
  return createHash('sha256').update(`${fact.source_url}\n${fact.claim}`).digest('hex').slice(0, 12);
}

/** Frappe un id à partir d'une clé d'identité. Sœur de `mintId`
 *  (gtav-poi-ids.mjs) : même discipline, préfixe différent — un item d'actu n'a
 *  ni jeu ni collection à porter dans son nom, et le schéma impose `^news_`. */
export function mintNewsId(key) {
  return `news_${createHash('sha256').update(key).digest('hex').slice(0, 8)}`;
}

function invalidReason(fact) {
  if (!fact.claim) return 'fait sans claim';
  if (!fact.source_url) return 'fait sans source_url — un item d’actu doit pouvoir être remonté à sa source';
  if (!ISO_DATE.test(fact.source_date ?? '')) return `date de source malformée : ${fact.source_date} (attendu AAAA-MM-JJ)`;
  if (!CONFIDENCES.has(fact.confidence)) return `confiance inconnue : ${fact.confidence}`;
  return null;
}

/**
 * @param facts     faits d'inbox, tous kinds confondus, aplatis depuis les
 *                  fichiers `.facts.json`
 * @param existing  [{ path, data }] — les fichiers actuels de content/news
 * @returns {{
 *   writes: Array<{path: string, data: object}>,        squelettes à écrire
 *   alreadyMaterialized: Array<{key: string, id: string}>, déjà couverts
 *   covered: Array<{fact: object, key: string, id: string}>, à marquer dans l'inbox
 *   skipped: Array<{claim: string, reason: string}>,    écartés, mais classés
 *   conflicts: Array<{claim: string, reason: string}>   si non vide, N'ÉCRIRE RIEN
 * }}
 */
export function materializeNews(facts, existing) {
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
    if (fact.kind !== 'news') {
      skipped.push({ claim: fact.claim, reason: `kind « ${fact.kind} » — pas de l'actu` });
      continue;
    }

    const problem = invalidReason(fact);
    if (problem) {
      conflicts.push({ claim: fact.claim, reason: problem });
      continue;
    }

    const key = identityKey(INBOX_SOURCE, 'news', factDiscriminant(fact));

    // Déjà matérialisé — par un run précédent, ou par un fait plus haut dans CE
    // lot. On se réapparie, on n'écrit pas un second item. Toute l'idempotence
    // tient là, et elle vient de la clé, pas d'un drapeau qu'on aurait oublié
    // de poser. L'item déjà rédigé n'est pas touché : la rédaction est une
    // décision humaine, la matérialisation ne l'écrase jamais.
    const previous = byProcessedFrom.get(key);
    if (previous) {
      alreadyMaterialized.push({ key, id: previous.data.id });
      covered.push({ fact, key, id: previous.data.id });
      continue;
    }

    const id = mintNewsId(key);
    if (byID.has(id)) {
      conflicts.push({ claim: fact.claim, reason: `l'id frappé ${id} existe déjà avec un autre processedFrom` });
      continue;
    }

    const data = {
      id,
      category: DEFAULT_CATEGORY,
      title: { ...PLACEHOLDER.title },
      body: { ...PLACEHOLDER.body },
      publishedAt: fact.source_date,
      status: 'draft',
      sources: [fact.source_url],
      confidence: fact.confidence,
      processedFrom: key,
      sourceClaim: fact.claim,
      needsRewrite: true,
    };
    const entry = { path: `content/news/${id}.json`, data };

    writes.push(entry);
    // Tenir les deux index à jour au fil du lot : sans ça, deux faits identiques
    // du même run produiraient deux fichiers de même id sans que rien ne le
    // signale.
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
