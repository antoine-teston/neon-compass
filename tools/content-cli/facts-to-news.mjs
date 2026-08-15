// Transformation pure « fait d'inbox → squelette content/news ». Aucune I/O,
// aucun accès distant : tout ce qui décide vit ici, et `cli.js` ne fait qu'écrire ce
// qu'on lui rend — même partage des rôles que `draft-to-poi.mjs`.
//
// Ce module existe pour une raison précise : la rédaction d'un item d'actu est
// le seul maillon de la chaîne qu'une machine ne peut pas faire seule (il faut
// reformuler un fait sans jamais reprendre une marque déposée). Tout le reste —
// identité, idempotence, garde-fous — doit donc être du code vérifiable, sinon
// le run hebdomadaire n'est pas automatisable : il dépendrait du jugement d'un
// modèle pour savoir ce qu'il a déjà publié.

import { createHash } from 'node:crypto';
import { explicitlyForbidden } from './source-policy.mjs';
import { identityKey } from '../basemap/gtav-poi-ids.mjs';
import { CARDINALITE, cleDeRefus, confianceSuperieure } from './vocabulaire.mjs';

/** Source d'identité des items nés de la veille — partie stable de la clé
 *  écrite dans `processedFrom`, et ce sur quoi le run suivant se réapparie. */
export const INBOX_SOURCE = 'inbox';

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/** Jeux que la veille peut désigner. Même vocabulaire que `MapGame` côté app.
 *  Un fait sans `game` porte sur le jeu à venir : c'était le seul sujet du fil
 *  avant qu'il ne s'ouvre aux deux. */
const GAMES = new Set(['leonida', 'gtav']);
const DEFAULT_GAME = 'leonida';
/** Doit rester le contrat exact de `data-scout` (.claude/agents/data-scout.md).
 *  Une valeur qu'il émet mais qu'on ne connaît pas ici devient un conflit — et
 *  un conflit bloque le lot ENTIER. Un seul fait `single-source` suffirait donc
 *  à faire perdre toute la veille de la semaine, en silence. */
const CONFIDENCES = new Set(['confirmed-official', 'multi-source', 'single-source', 'rumor']);

/** Le kind que ce module matérialise. Sa cardinalité est lue dans la table
 *  plutôt que supposée : la basculer sur `multiple` éteint le contrôle, ce qui
 *  est exactement ce que la table est censée décider. */
const KIND = 'news';

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
  // Le registre a BANNI cet hôte : le fait cite ce que la veille n'a pas le
  // droit de lire, la faute est en amont (scout, ou politique qui a changé).
  // Elle passe par `conflicts` comme une date malformée — le run s'arrête, on
  // purge l'inbox, on ne matérialise pas à côté. Trou constaté le 2026-08-15 :
  // deux faits du 21/07 citaient rockstargames.com et gtacodes.io sans qu'aucun
  // contrôle ne compare jamais source_url au registre.
  if (explicitlyForbidden(fact.source_url)) return `hôte banni du registre : ${fact.source_url}`;
  if (!ISO_DATE.test(fact.source_date ?? '')) return `date de source malformée : ${fact.source_date} (attendu AAAA-MM-JJ)`;
  if (!CONFIDENCES.has(fact.confidence)) return `confiance inconnue : ${fact.confidence}`;
  if (fact.game !== undefined && !GAMES.has(fact.game)) return `jeu inconnu : ${fact.game}`;
  return null;
}

/**
 * @param facts     faits d'inbox, tous kinds confondus, aplatis depuis les
 *                  fichiers `.facts.json`
 * @param existing  [{ path, data }] — les fichiers actuels de content/news
 * @param refus     le registre des refus, LU PAR L'APPELANT — ce module reste
 *                  pur. `{}` par défaut : sans registre, rien ne change.
 * @returns {{
 *   writes: Array<{path: string, data: object}>,        squelettes à écrire
 *   alreadyMaterialized: Array<{key: string, id: string}>, déjà couverts
 *   covered: Array<{fact: object, key: string, id: string}>, à marquer dans l'inbox
 *   skipped: Array<{claim: string, reason: string}>,    écartés, mais classés
 *   ecartes: Array<{url, claim, raison, par}>,          jetés, et pourquoi
 *   leves: Array<{url, de, a, le}>,                     refus levés, et par quoi
 *   conflicts: Array<{claim: string, reason: string}>   si non vide, N'ÉCRIRE RIEN
 * }}
 */
export function materializeNews(facts, existing, refus = {}) {
  const byID = new Map(existing.map((entry) => [entry.data.id, entry]));
  const byProcessedFrom = new Map(
    existing.filter((entry) => entry.data.processedFrom).map((entry) => [entry.data.processedFrom, entry]),
  );

  // L'index des URL déjà portées. C'est le « registre des URL récoltées » de la
  // spec — il ne s'écrit nulle part : il EST le contenu déjà là.
  const parSource = new Map();
  for (const entry of existing) {
    for (const url of entry.data.sources ?? []) {
      if (!parSource.has(url)) parSource.set(url, entry.data.id);
    }
  }

  const writes = [];
  const alreadyMaterialized = [];
  const covered = [];
  const skipped = [];
  const ecartes = [];
  const leves = [];
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

    // LE CONTRÔLE DE CONVERGENCE.
    //
    // Après `byProcessedFrom` et pas avant : un fait qui se réapparie à SON
    // entrée est « déjà matérialisé », pas « écarté ». Les confondre dirait
    // qu'on a jeté quelque chose alors qu'on a reconnu.
    //
    // Le claim n'entre pas dans la décision — c'est ce qui rend le contrôle
    // insensible à la reformulation, donc capable de voir deux sessions
    // concurrentes là où `factDiscriminant` voyait deux faits distincts.
    if (CARDINALITE[KIND] === 'une') {
      const deja = parSource.get(fact.source_url);
      if (deja) {
        ecartes.push({
          url: fact.source_url,
          claim: fact.claim,
          raison: 'URL déjà couverte',
          par: deja,
        });
        continue;
      }
    }

    // Le refus, et sa levée.
    //
    // Après le contrôle d'URL : si une entrée porte déjà cette URL, le refus
    // est sans objet — un item écarté a été supprimé, donc rien ne la porte.
    const refuse = refus[cleDeRefus(KIND, fact.source_url)];
    if (refuse) {
      if (!confianceSuperieure(fact.confidence, refuse.confiance)) {
        ecartes.push({
          url: fact.source_url,
          claim: fact.claim,
          raison: `refus du ${refuse.le} — ${refuse.motif}`,
          par: refuse.entree,
        });
        continue;
      }
      // Le 2026-08-09 n'a pas écarté un sujet, il a écarté une rumeur.
      leves.push({ url: fact.source_url, de: refuse.confiance, a: fact.confidence, le: refuse.le });
    }

    const id = mintNewsId(key);
    if (byID.has(id)) {
      conflicts.push({ claim: fact.claim, reason: `l'id frappé ${id} existe déjà avec un autre processedFrom` });
      continue;
    }

    const data = {
      id,
      category: DEFAULT_CATEGORY,
      game: fact.game ?? DEFAULT_GAME,
      title: { ...PLACEHOLDER.title },
      body: { ...PLACEHOLDER.body },
      publishedAt: fact.source_date,
      status: 'draft',
      // La liste complète si le scout l'a fournie (même contrat que
      // facts-to-online-event) : `check-publishable` exige >= 2 hôtes distincts
      // pour `multi-source`, et ne garder que source_url détruirait la preuve.
      // L'IDENTITÉ du fait, elle, reste source_url + claim.
      sources: fact.sources?.length ? fact.sources : [fact.source_url],
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
    // Sans cette ligne, deux faits du MÊME lot portant la même URL passeraient
    // tous les deux : l'index ne connaîtrait que les entrées d'avant le run.
    parSource.set(fact.source_url, id);
  }

  // Un conflit invalide le lot entier : matérialiser la moitié d'un run
  // laisserait l'inbox à moitié marquée, et le fait fautif reviendrait au run
  // suivant sans qu'on sache ce qui a déjà été fait.
  if (conflicts.length) {
    return { writes: [], alreadyMaterialized: [], covered: [], skipped: [], ecartes: [], leves: [], conflicts };
  }

  return { writes, alreadyMaterialized, covered, skipped, ecartes, leves, conflicts };
}
