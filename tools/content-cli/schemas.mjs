// Les kinds de `content/`, leurs schémas compilés, et le chargement de l'arbre.
//
// Extrait de `cli.js` le 2026-08-07, sans changement de comportement, parce que
// la console (`ui/drafts.mjs`) doit valider un item isolé sans lancer la CLI —
// et qu'une porte qui n'exécute aucun processus ne peut pas passer par `spawn`.
//
// `cli.js` reste le seul point d'entrée en ligne de commande ; ce module ne
// connaît ni `console`, ni `process.exit`, ni les drapeaux.

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv/dist/2020.js';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const CONTENT = join(ROOT, 'content');

const ajv = new Ajv({ allErrors: true });

// Les schémas bruts sont gardés en plus des compilés : la console a besoin de
// lire les `enum` pour proposer les valeurs possibles d'un champ, et un
// validateur ajv compilé ne rend pas son schéma source.
const SCHEMA_FILES = {
  poi: 'poi.schema.json',
  cheats: 'cheat.schema.json',
  collections: 'collection.schema.json',
  news: 'news.schema.json',
  'online-events': 'online-event.schema.json',
};

export const rawSchemas = Object.fromEntries(
  Object.entries(SCHEMA_FILES).map(([name, file]) => [
    name,
    JSON.parse(readFileSync(join(CONTENT, 'schema', file))),
  ]),
);

const compiled = Object.fromEntries(
  Object.entries(rawSchemas).map(([name, schema]) => [name, ajv.compile(schema)]),
);

// Un « kind » est un répertoire de content/. Il porte son schéma et le nom de
// collection publié sur le CDN.
//
// `poi-gtav` et `poi` partagent le schéma mais PAS la collection : les positions
// de la fixture sont normalisées sur la carte de référence, les afficher sur
// celle du jeu à venir poserait des centaines de pins à des endroits qui ne
// veulent rien dire. La séparation est délibérée côté app aussi
// (NeonCompass/Features/Map/MapModel.swift, `pois(for:)`).
export const KINDS = {
  poi: { schema: 'poi', collection: 'poi' },
  'poi-gtav': { schema: 'poi', collection: 'poi_gtav' },
  cheats: { schema: 'cheats', collection: 'cheats' },
  collections: { schema: 'collections', collection: 'collections' },
  news: { schema: 'news', collection: 'news' },
  'online-events': { schema: 'online-events', collection: 'online_events' },
};

/** L'echelle de confiance, du plus FAIBLE au plus FORT.
 *
 *  L'enumeration de `news.schema.json` la donne dans l'ordre inverse ; un test
 *  compare les deux ENSEMBLES, pour qu'ajouter un niveau au schema fasse tomber
 *  la suite au lieu de creer une comparaison muette. */
export const CONFIANCE_ORDRE = ['rumor', 'single-source', 'multi-source', 'confirmed-official'];

/** Combien d'entrees une meme URL source a le droit de produire, par kind.
 *
 *  `une` declenche le controle de convergence ; `multiple` l'eteint. Les POI le
 *  sont parce qu'un article « toutes les localisations confirmees » en donne
 *  legitimement trois — c'est ainsi que les 537 POI sont arrives. */
export const CARDINALITE = {
  news: 'une',
  poi: 'multiple',
  'poi-gtav': 'multiple',
  cheats: 'multiple',
  collections: 'multiple',
};

/** Les kinds que le controle d'URL ne juge PAS, et pourquoi.
 *
 *  Deux tables plutot qu'un defaut : inscrire `online-events` dans
 *  `CARDINALITE` suggererait qu'il est couvert par ce controle-ci alors qu'il
 *  l'est par le sien ; le taire laisserait croire a un oubli. */
export const HORS_CONTROLE = {
  'online-events':
    'identite portee par windowDiscriminant (debut de fenetre), deja insensible au claim',
};

export const schemas = Object.fromEntries(
  Object.entries(KINDS).map(([kind, { schema }]) => [kind, compiled[schema]]),
);

export function loadAll() {
  const entries = [];
  for (const kind of Object.keys(KINDS)) {
    const dir = join(CONTENT, kind);
    // Un kind dont le répertoire n'existe pas encore n'est pas une erreur : il
    // est simplement vide. Sans ce garde-fou, déclarer un kind avant sa première
    // matérialisation ferait échouer TOUTES les commandes, `pull-news` comprise
    // — c'est-à-dire précisément celle qui crée le répertoire.
    if (!existsSync(dir)) continue;
    for (const f of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
      entries.push({ kind, file: `${kind}/${f}`, data: JSON.parse(readFileSync(join(dir, f))) });
    }
  }
  return entries;
}

/**
 * Valide un item isolé. Rend un tableau de messages, vide si l'item passe —
 * la même forme que `problemsFor`, pour que l'appelant traite les deux
 * refus de la même façon.
 *
 * `schemas[kind]` est un validateur ajv réutilisé : ses `errors` sont écrasées
 * au prochain appel, d'où la copie immédiate.
 */
export function schemaProblemsFor(kind, data) {
  const validator = schemas[kind];
  if (!validator) return [`kind inconnu : ${kind}`];
  if (validator(data)) return [];
  return (validator.errors ?? []).map((e) => `${e.instancePath || '/'} ${e.message}`);
}
