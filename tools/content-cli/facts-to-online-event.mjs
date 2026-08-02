// Transformation pure « fait d'inbox → squelette content/online-events ».
// Même partage des rôles que `facts-to-news.mjs` : aucune I/O, `cli.js` ne
// fait qu'écrire ce qu'on lui rend.
//
// Le fait d'inbox d'un événement en ligne porte le même vocabulaire qu'un fait
// `news` — `claim`, `source_url`, `source_date`, `game`, `confidence` — plus
// deux champs propres à ce kind : `starts_at` et `ends_at` (UTC complet), la
// fenêtre qui justifie le compte à rebours. Sans elle il n'y a rien à
// afficher qu'un `news` ne dirait déjà.
//
// L'identité emprunte la mécanique de `news` (`identityKey` — gtav-poi-ids.mjs)
// mais PAS son discriminant. Voir `windowDiscriminant` : ce kind est le seul dont
// le contenu peut changer après coup, et un discriminant qui hache le contenu
// s'y comporte mal.

import { createHash } from 'node:crypto';
import { identityKey } from '../basemap/gtav-poi-ids.mjs';
import { INBOX_SOURCE } from './facts-to-news.mjs';

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

/**
 * Ce qui distingue une fenêtre d'une autre : sa source, son jeu, et son DÉBUT.
 *
 * Pourquoi pas `factDiscriminant` (facts-to-news.mjs), qui hache
 * `source_url + claim` et sert à tous les autres kinds : une entrée d'actu est
 * immuable — publiée, elle ne change plus — alors qu'une fenêtre du mode en ligne
 * MUTE. La source le dit elle-même : Rockstar prolonge parfois un événement. Une
 * prolongation change la fin de fenêtre, donc le claim, donc le discriminant,
 * donc l'`id` : au lieu de corriger le compte à rebours, on créait une SECONDE
 * entrée chevauchant la première, et l'app en choisissait une au hasard.
 *
 * Le début, lui, ne bouge pas — une semaine qui a commencé a commencé. Il porte
 * donc l'identité, et la fin devient une donnée révisable comme les autres.
 *
 * Corollaire voulu : une phase 2 d'un événement de deux semaines a son propre
 * début, donc sa propre entrée. C'est bien ce que le compte à rebours doit
 * annoncer — la fin de la phase en cours, pas celle de l'événement entier.
 */
export function windowDiscriminant(fact) {
  const game = fact.game ?? DEFAULT_GAME;
  return createHash('sha256').update(`${fact.source_url}\n${game}\n${fact.starts_at}`).digest('hex').slice(0, 12);
}

/**
 * Ce qu'une nouvelle lecture de la source a autorité pour corriger, en DEUX
 * étages — parce que « qui possède ce champ » n'a pas la même réponse partout.
 *
 * `WINDOW` : la fenêtre appartient à la machine, toujours, sur n'importe quelle
 * entrée. Aucun humain ne l'écrit — `content-editor.md` le lui interdit
 * explicitement (« Tu ne les modifies pas : si elles sont fausses, c'est un fait
 * à corriger en amont »). C'est aussi la seule révision qui compte vraiment : une
 * prolongation d'événement rend le compte à rebours faux, et un compte à rebours
 * faux est pire qu'une absence.
 *
 * `CONTENT` : tout le reste peut avoir été écrit par quelqu'un. On ne le révise
 * que sur une entrée dont la machine est l'unique auteur, reconnaissable à un
 * `needsRewrite: false` PRÉSENT — c'est sa signature (`factToOnlineEvent` écrit
 * toujours la clé). Un squelette rédigé à la main, lui, voit la clé SUPPRIMÉE :
 * c'est ce qui distingue « la machine a tout écrit » de « quelqu'un a pris le
 * relais ». Un test l'exigeait déjà, et il avait raison de le faire.
 *
 * Jamais révisés : `status` (publier reste une décision humaine, une correction
 * de fenêtre ne la reprend pas) et `id`/`processedFrom`, qui SONT l'identité.
 */
const WINDOW_FIELDS = ['startsAt', 'endsAt'];
const CONTENT_FIELDS = ['title', 'bonuses', 'discounts', 'podiumVehicle', 'sources', 'confidence', 'sourceClaim', 'game'];

/** La machine est-elle l'unique auteur de cette entrée ? */
export function machineAuthored(entry) {
  return entry.needsRewrite === false;
}

/** @returns les champs révisables qui diffèrent, `[]` si l'entrée est à jour. */
export function revisedFields(existing, fresh) {
  const fields = machineAuthored(existing) && machineAuthored(fresh) ? [...WINDOW_FIELDS, ...CONTENT_FIELDS] : WINDOW_FIELDS;
  return fields.filter((field) => JSON.stringify(existing[field]) !== JSON.stringify(fresh[field]));
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

  // Un fait STRUCTURÉ porte déjà ses bonus et ses remises — c'est le cas de
  // ceux que `weekly-hub.mjs` normalise depuis le payload de la source. Il n'y a
  // alors plus rien à rédiger : les noms d'activités et de biens sont des faits
  // (comme les noms de POI), et les étiquettes sont composées dans les cinq
  // langues sans marque. `needsRewrite` tombe, et l'entrée est relisible telle
  // quelle. Un fait sans ces champs reste ce qu'il était : un squelette à
  // rédiger par `content-editor`.
  const structured = fact.bonuses !== undefined || fact.discounts !== undefined;
  if (structured) {
    assertLocalizedList(fact.bonuses, 'bonuses', ['activity', 'label']);
    assertDiscountList(fact.discounts);
  }

  const key = identityKey(INBOX_SOURCE, 'online-events', windowDiscriminant(fact));

  return {
    id: mintOnlineEventId(key),
    game: fact.game ?? DEFAULT_GAME,
    startsAt: fact.starts_at,
    endsAt: fact.ends_at,
    // Squelette : le titre est une étiquette neutre, jamais la revendication
    // de la source — elle cite ses marques mot pour mot. Un fait structuré
    // apporte le sien, déjà localisé.
    title: fact.title ?? { en: `Weekly update — ${fact.starts_at.slice(0, 10)}` },
    bonuses: fact.bonuses ?? [],
    discounts: fact.discounts ?? [],
    status: 'draft',
    // Un fait peut citer plusieurs URL de la même semaine (le hub ET l'article
    // qui la raconte) : la traçabilité y gagne, la confiance non — deux pages
    // d'un même éditeur restent une source.
    sources: fact.sources ?? [fact.source_url],
    confidence: fact.confidence,
    processedFrom: key,
    // La prose de la source quand on l'a, le claim sinon. C'est le corpus
    // auquel `check-originality.mjs` compare les champs rédigés : un résumé le
    // viderait de sa substance.
    sourceClaim: fact.source_prose ?? fact.claim,
    needsRewrite: !structured,
  };
}

/** Les deux gardes ci-dessous font échouer un fait structuré mal formé ICI, au
 *  lieu de le laisser produire un fichier que le `validate` suivant refusera —
 *  noyé parmi les entrées saines, et sans dire quel fait d'inbox l'a produit. */
function assertLocalized(value, path) {
  if (!value || typeof value !== 'object' || typeof value.en !== 'string' || !value.en) {
    throw new Error(`${path} : texte localisé attendu, avec au moins « en »`);
  }
}

function assertLocalizedList(list, name, fields) {
  if (list === undefined) return;
  if (!Array.isArray(list)) throw new Error(`${name} : tableau attendu`);
  list.forEach((entry, index) => {
    for (const field of fields) assertLocalized(entry?.[field], `${name}[${index}].${field}`);
  });
}

function assertDiscountList(list) {
  if (list === undefined) return;
  if (!Array.isArray(list)) throw new Error('discounts : tableau attendu');
  list.forEach((entry, index) => {
    assertLocalized(entry?.item, `discounts[${index}].item`);
    const { percent } = entry;
    if (!Number.isInteger(percent) || percent < 1 || percent > 100) {
      throw new Error(`discounts[${index}].percent : entier 1-100 attendu, reçu ${percent}`);
    }
  });
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
 *   writes: Array<{path: string, data: object}>,        entrées neuves à écrire
 *   updates: Array<{path: string, data: object, changes: string[]}>, fenêtres révisées
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
  const updates = [];
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
    // CE lot. On se réapparie, on n'écrit pas un second item.
    const previous = byProcessedFrom.get(key);
    if (previous) {
      // Une fenêtre MUTE : la source prolonge parfois un événement, ou corrige
      // une remise. L'entrée doit alors être révisée, pas doublée — c'était le
      // défaut que l'identité par le contenu masquait (windowDiscriminant).
      //
      // Ce qui est révisable, et pour qui, est tranché par `revisedFields` : la
      // fenêtre appartient toujours à la machine, le reste seulement quand elle
      // est l'unique auteur de l'entrée. `status` n'est jamais touché — une entrée
      // publiée dont la fenêtre est prolongée RESTE publiée avec la bonne fin,
      // c'est précisément ce qu'on veut, et un brouillon ne se publie pas seul.
      //
      // La révision d'une entrée déjà publiée modifie ce qui est en ligne. Elle
      // n'est pas silencieuse pour autant : elle est listée au compte-rendu du
      // run et arrive dans le diff d'une PR, où un humain peut la refuser. Même
      // garantie que tout le reste de cette chaîne.
      const changes = revisedFields(previous.data, data);
      if (changes.length) {
        const revised = { ...previous.data };
        for (const field of changes) {
          if (data[field] === undefined) delete revised[field];
          else revised[field] = data[field];
        }
        const entry = { path: previous.path, data: revised, changes };
        updates.push(entry);
        // Réapparier l'index sur la version révisée : deux faits du même lot
        // visant la même fenêtre ne doivent pas produire deux révisions.
        byProcessedFrom.set(key, entry);
        byID.set(revised.id, entry);
      } else {
        alreadyMaterialized.push({ key, id: previous.data.id });
      }
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
    return { writes: [], updates: [], alreadyMaterialized: [], covered: [], skipped: [], conflicts };
  }

  return { writes, updates, alreadyMaterialized, covered, skipped, conflicts };
}
