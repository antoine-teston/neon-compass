// Frappe et réconciliation des identifiants de POI GTA V.
//
// Ces fonctions sont isolées du script d'import parce qu'elles portent le seul
// invariant vraiment irréversible du pipeline : un id publié ne doit JAMAIS
// désigner un autre POI. FoundEntry (progression de l'utilisateur) ne stocke
// qu'une chaîne — un id réattribué déplace silencieusement la progression de
// tout le monde. D'où un module à part, testable seul (gtav-poi-ids.test.mjs).
//
// Le modèle : on frappe une fois, on lit ensuite. Les fichiers déjà présents
// dans content/poi-gtav/ SONT le registre (chacun porte son `processedFrom`),
// il n'y a pas de table parallèle à maintenir.

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

/** Arrondit une coordonnée monde au décimètre, en évitant le « -0.0 » que
 *  toFixed produit pour les très petits négatifs — deux runs doivent produire
 *  exactement la même chaîne. */
export function formatWorldCoord(value, decimals = 1) {
  const rounded = Number(value.toFixed(decimals));
  return (Object.is(rounded, -0) ? 0 : rounded).toFixed(decimals);
}

/** Discriminant d'une entrée sans identifiant amont : ses coordonnées monde.
 *  Volontairement les coordonnées MONDE et non les normalisées — recalibrer la
 *  projection ferait bouger les secondes, donc changerait toutes les clés.
 *
 *  `decimals` monte à 5 pour les sources en lat/lng, dont l'amplitude est de
 *  quelques unités : au décimètre deux POI distincts s'y confondraient. */
export function worldDiscriminant(x, y, decimals = 1) {
  return `X=${formatWorldCoord(x, decimals)},Y=${formatWorldCoord(y, decimals)}`;
}

/** Vrai si la source réutilise un même id amont pour des entrées distinctes.
 *  gta5-map le fait (4 cas). La détection se fait en scannant la source ENTIÈRE
 *  avant d'émettre quoi que ce soit : la décision ne dépend donc pas de l'ordre
 *  d'itération, contrairement au suffixage `_2` qu'elle remplace. */
export function hasDuplicateUpstreamIds(ids) {
  const seen = new Set();
  for (const id of ids) {
    const key = String(id);
    if (seen.has(key)) return true;
    seen.add(key);
  }
  return false;
}

/** Clé d'identité stable d'un POI : `<source>:<collection>:<discriminant>`.
 *  C'est ce qui est écrit dans `processedFrom`, et c'est sur quoi les runs
 *  suivants se réapparient. */
export function identityKey(source, collection, discriminant) {
  return `${source}:${collection}:${discriminant}`;
}

/** Frappe un id à partir d'une clé d'identité. Appelée UNE SEULE FOIS par POI,
 *  au premier import ; ensuite l'id vient du fichier existant. Le hash n'est
 *  pas une dérivation qu'on recalcule — c'est une machine à tirer des noms
 *  uniques et déterministes. */
export function mintId(game, collection, key) {
  const digest = createHash('sha256').update(key).digest('hex').slice(0, 8);
  return `poi_${game}_${collection}_${digest}`;
}

/** Champs qui appartiennent au fichier, pas à la source.
 *
 *  Le pipeline est autorité sur ce qu'il DÉRIVE de l'amont (position, titre,
 *  catégorie, collection, sources). Il ne l'est pas sur les décisions humaines :
 *  publier une entrée, la marquer comme doublon d'une autre, la retirer. Sans
 *  cette liste, un ré-import remettrait les 537 POI en `draft` et effacerait
 *  toutes les pierres tombales — silencieusement. */
export const EDITORIAL_FIELDS = ['status', 'mergedInto', 'deleted'];

/** Champs localisés d'un POI, et langues que le pipeline ne produit pas lui-même.
 *  L'anglais est exclu : il vient de l'amont, il n'est jamais reporté. */
const LOCALIZED_FIELDS = ['title', 'note'];
const TRANSLATED_LANGUAGES = ['fr', 'es', 'it', 'de'];

/**
 * Reporte sur une entrée fraîche les traductions déjà écrites pour la même clé.
 *
 * Même raison d'être que EDITORIAL_FIELDS : traduire est une décision qui vit
 * dans le fichier, pas dans la source. Sans ce report, un ré-import rendrait
 * muettes les 389 traductions FR d'un coup, et rien ne le signalerait — l'app
 * replierait simplement sur l'anglais.
 *
 * Deux garde-fous délibérés :
 *  - on ne reporte que si l'`en` est IDENTIQUE. Un libellé amont retouché rend
 *    sa traduction périmée ; mieux vaut un champ manquant, que `translate`
 *    reverra, qu'une traduction qui ne dit plus la même chose.
 *  - on ne recouvre jamais une langue que le pipeline vient d'émettre (le `fr`
 *    dérivé de la table TYPES). Il reste autorité sur ce qu'il dérive, ici on
 *    ne fait que combler ce qu'il laisse vide.
 */
export function carryTranslations(fresh, previous) {
  if (!previous) return fresh;
  const carried = { ...fresh };
  for (const field of LOCALIZED_FIELDS) {
    const before = previous[field];
    const after = carried[field];
    if (!before || !after || before.en !== after.en) continue;
    const merged = { ...after };
    for (const lang of TRANSLATED_LANGUAGES) {
      if (merged[lang] === undefined && before[lang] !== undefined) merged[lang] = before[lang];
    }
    carried[field] = merged;
  }
  return carried;
}

/** Indexe les fichiers déjà présents : `processedFrom` -> document complet.
 *  Renvoie une Map vide si le répertoire n'existe pas (premier run). */
export function loadExisting(dir) {
  const index = new Map();
  if (!existsSync(dir)) return index;
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
    const data = JSON.parse(readFileSync(join(dir, file), 'utf8'));
    if (data.processedFrom) index.set(data.processedFrom, data);
  }
  return index;
}

/**
 * Écarte les entrées strictement identiques à une déjà vue.
 *
 * Certaines sources listent deux fois la même entité : le dump `garages.json`
 * contient chacun de ses 16 garages en double, champ pour champ (même Name,
 * même Hash, même Position). Indexé sur le rang, l'ancien pipeline en faisait
 * 32 POI — deux pins empilés au même pixel pour chaque garage.
 *
 * Même clé + même contenu = la même chose, on n'en garde qu'une. Même clé mais
 * contenu différent est une tout autre affaire : ce n'est pas un doublon, c'est
 * un discriminant trop grossier, et on laisse `reconcileIds` lever.
 */
export function dedupeIdenticalEntries(pois) {
  const byKey = new Map();
  const kept = [];
  let dropped = 0;
  for (const poi of pois) {
    const seen = byKey.get(poi.processedFrom);
    // Comparaison par sérialisation : tous ces objets sont construits par le
    // même code, donc l'ordre des clés est identique par construction.
    if (seen && JSON.stringify(seen) === JSON.stringify(poi)) {
      dropped++;
      continue;
    }
    if (!seen) byKey.set(poi.processedFrom, poi);
    kept.push(poi);
  }
  return { pois: kept, dropped };
}

/**
 * Réconcilie les POI d'un run avec les ids déjà attribués.
 *
 * Trois issues par POI :
 *  - clé connue      -> on réutilise l'id existant (le cas normal)
 *  - clé inconnue    -> on frappe un id neuf
 *  - clé disparue    -> orpheline : signalée, jamais supprimée d'office, et son
 *                       id n'est jamais recyclé pendant ce run
 *
 * Lève si deux POI du run produisent la même clé d'identité. C'est délibéré :
 * l'ancien `uniqueId()` suffixait `_2` en silence selon l'ordre d'itération,
 * ce qui est exactement le bug qu'on élimine. Une collision est une erreur de
 * configuration de source, pas quelque chose à rattraper au vol.
 */
export function reconcileIds(pois, existing, { game = 'gtav' } = {}) {
  const seenKeys = new Map();
  const mintedIds = new Set([...existing.values()].map((doc) => doc.id));
  const resolved = [];
  let reused = 0;
  let minted = 0;

  for (const poi of pois) {
    const key = poi.processedFrom;
    if (seenKeys.has(key)) {
      throw new Error(
        `clé d'identité dupliquée : ${key}\n` +
          `  déjà utilisée par « ${seenKeys.get(key)} », re-proposée par « ${poi.title.en} »\n` +
          `  -> la source a besoin d'un discriminant à coordonnées (voir hasDuplicateUpstreamIds)`,
      );
    }
    seenKeys.set(key, poi.title.en);

    const previous = existing.get(key);
    let id = previous?.id;
    if (id) {
      reused++;
    } else {
      id = mintId(game, poi.collection, key);
      if (mintedIds.has(id)) {
        throw new Error(`collision de hash sur ${id} (clé ${key}) — élargir le digest`);
      }
      minted++;
    }
    mintedIds.add(id);

    // Les décisions humaines déjà prises sur ce POI survivent au ré-import :
    // son statut éditorial, et les traductions déjà écrites pour ses libellés.
    const editorial = {};
    for (const field of EDITORIAL_FIELDS) {
      if (previous?.[field] !== undefined) editorial[field] = previous[field];
    }
    resolved.push({ id, ...carryTranslations(poi, previous), ...editorial });
  }

  const liveKeys = new Set(pois.map((p) => p.processedFrom));
  const orphaned = [...existing.entries()]
    .filter(([key]) => !liveKeys.has(key))
    .map(([key, doc]) => ({ key, id: doc.id }));

  return { pois: resolved, reused, minted, orphaned };
}
