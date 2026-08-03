#!/usr/bin/env node
// Importe les POI de la carte de référence GTA V au schéma content/schema/
// poi.schema.json, et régénère le fixture embarqué que l'app lit réellement
// (Resources/POI/seed-poi.json — cf. POILoader.loadSeed).
//
//   node gtav-poi.mjs [--out content/poi-gtav] [--no-seed] [--render] [--prune]
//
// Le script FUSIONNE, il ne régénère pas : les fichiers déjà présents portent
// chacun leur `processedFrom` (clé d'identité stable), et leur `id` est réutilisé
// tel quel. Un id publié ne doit jamais désigner un autre POI — FoundEntry ne
// stocke qu'une chaîne, donc un id réattribué déplace silencieusement la
// progression de tous les utilisateurs. Voir gtav-poi-ids.mjs.
//
// --prune supprime les fichiers devenus orphelins (clé absente de l'amont).
// Sans lui ils sont seulement signalés : leur disparition mérite un coup d'œil
// humain avant qu'on libère leur id.
//
// Les POI atterrissent dans content/poi-gtav/ et NON dans content/poi/ : ce
// dernier porte le contenu éditorial GTA VI qui part vers le CDN, et
// content-cli check-publishable / publish balaient tout ce répertoire. Mélanger
// une fixture de dev de ~1 000 entrées avec les 7 POI éditoriaux exposerait la
// fixture à une publication accidentelle.
//
// --render produit un PNG de contrôle (pins sur la carte) : c'est la seule
// vérification qui attrape un désalignement du géoréférencement, un schéma
// valide ne le voit pas.

import { mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import Ajv from 'ajv/dist/2020.js';
import { mercatorToNorm, worldToNorm, inBounds, fetchRetry, pool } from './gtav-geo.mjs';
import { isOceanNC, isOceanRaw } from './gtav-restyle.mjs';
import {
  dedupeIdenticalEntries,
  hasDuplicateUpstreamIds,
  identityKey,
  loadExisting,
  reconcileIds,
  worldDiscriminant,
} from './gtav-poi-ids.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}
const outDir = arg('out', join(ROOT, 'content', 'poi-gtav'));
const writeSeed = !process.argv.includes('--no-seed');
const doRender = process.argv.includes('--render');
const doPrune = process.argv.includes('--prune');

const DANHARPER = 'https://raw.githubusercontent.com/danharper/GTAV/master/locations.json';
const GTA5MAP = 'https://raw.githubusercontent.com/gta5-map/gta5-map.github.io/master/locations.json';
const DUMPS = 'https://raw.githubusercontent.com/DurtyFree/gta-v-data-dumps/master';

// Le schéma n'a que 6 catégories : chaque type source est rangé dans la moins
// fausse, et `slug` sert à construire des id stables (^poi_[a-z0-9_]+$).
// `fr` traduit le libellé de type ; les toponymes restent tels quels.
const TYPES = {
  'Nuclear Waste':    { category: 'collectible', slug: 'nuclear_waste',  fr: 'Déchets nucléaires' },
  'Spaceship Part':   { category: 'collectible', slug: 'spaceship_part', fr: 'Pièce de vaisseau' },
  'Letter Scrap':     { category: 'collectible', slug: 'letter_scrap',   fr: 'Fragment de lettre' },
  'Epsilon Tract':    { category: 'collectible', slug: 'epsilon_tract',  fr: 'Tract Epsilon' },
  Money:              { category: 'collectible', slug: 'hidden_cash',    fr: 'Magot caché' },
  'Stunt Jump':       { category: 'activity',    slug: 'stunt_jump',     fr: 'Saut cascade' },
  'Knife Flight':     { category: 'activity',    slug: 'knife_flight',   fr: 'Vol en rase-mottes' },
  'Under the Bridge': { category: 'activity',    slug: 'under_bridge',   fr: 'Passage sous pont' },
  'Wall breaches':    { category: 'activity',    slug: 'wall_breach',    fr: 'Passage de mur' },
  Glitches:           { category: 'activity',    slug: 'glitch',         fr: 'Anomalie' },
  'Vehicle Spawn':    { category: 'vehicle',     slug: 'vehicle_spawn',  fr: 'Apparition de véhicule' },
  'Epsilon Car':      { category: 'vehicle',     slug: 'epsilon_car',    fr: 'Véhicule Epsilon' },
  Vehicles:           { category: 'vehicle',     slug: 'story_vehicle',  fr: 'Véhicule de récit' },
};

// Jeux en coordonnées monde du jeu. Volontairement restreint aux objets ayant
// un intérêt joueur : les autres dumps (lampadaires, poubelles, bancs, bornes
// incendie…) sont du mobilier urbain, utile seulement comme test de charge.
// Retirés volontairement : les 121 distributeurs et les 340 intérieurs MLO.
// Ils pesaient à eux seuls 61 % de la fixture, écrasaient la couleur dominante
// de presque tous les agrégats, et n'ont pas d'intérêt joueur — un distributeur
// n'est pas un point d'intérêt, c'est du mobilier. Les jeux restent
// disponibles dans le dump amont si on veut les réintroduire.
const WORLD_SETS = [
  { file: 'objectslocations/worldGasPumps.json',  slug: 'gas',      category: 'landmark', en: 'Gas Station',  fr: 'Station-service' },
  {
    file: 'garages.json', slug: 'garage', category: 'safehouse', en: 'Garage', fr: 'Garage',
    // Les garages sont déjà nommés lisiblement en amont (« Michael - Beverly
    // Hills »), inutile de les étiqueter tous « Garage ».
    title: (e) => ({ en: `Garage — ${e.Name}`, fr: `Garage — ${e.Name}` }),
    // Ce nom entre aussi dans la clé d'identité, en plus des coordonnées :
    // aucun des deux ne suffit seul. Deux lockups distincts partagent le même
    // point arrondi (Lockup_PSY_01 et _02 en X=2337.6,Y=3122.5), et deux
    // garages distincts partagent le même nom (« Michael - Beverly Hills »).
    key: (e) => e.Name,
  },
];

/** Traduit « Letter Scrap #3 - Paleto Bay » en « Fragment de lettre #3 - Paleto
 *  Bay » : seul le libellé de type est remplacé, le numéro et le toponyme sont
 *  conservés. Renvoie null si le titre ne commence pas par le type (titres
 *  propres comme « Declasse Tornado »), auquel cas on n'invente pas de FR. */
function frTitle(title, type, fr) {
  return title.startsWith(type) ? fr + title.slice(type.length) : null;
}

const pois = [];

// --- 1. Jeux en lat/lng Web Mercator -------------------------------------
for (const [url, label] of [[DANHARPER, 'danharper/GTAV'], [GTA5MAP, 'gta5-map']]) {
  const entries = JSON.parse(await fetchRetry(url));
  const candidates = [];
  let dropped = 0;
  for (const e of entries) {
    const t = TYPES[e.type];
    if (!t) { dropped++; continue; }
    const p = mercatorToNorm(e.lat, e.lng);
    // Le jeu danharper contient un marqueur parasite hors carte, laissé par le
    // handler de clic-droit de l'auteur.
    if (!inBounds(p)) { dropped++; continue; }
    candidates.push({ e, t, p });
  }

  // Décidé sur la source ENTIÈRE avant d'émettre quoi que ce soit : gta5-map
  // réutilise 4 id amont, et le tri-bris par coordonnées doit s'appliquer
  // uniformément. L'appliquer au premier doublon rencontré rendrait la clé
  // dépendante de l'ordre d'itération — le bug qu'on élimine.
  const needsCoordTiebreak = hasDuplicateUpstreamIds(candidates.map(({ e }) => e.id));
  if (needsCoordTiebreak) console.log(`${label.padEnd(16)} id amont non uniques -> discriminant à coordonnées`);

  for (const { e, t, p } of candidates) {
    const fr = frTitle(e.title, e.type, t.fr);
    pois.push({
      category: t.category,
      collection: t.slug,
      position: { x: Number(p.x.toFixed(6)), y: Number(p.y.toFixed(6)) },
      title: fr ? { en: e.title, fr } : { en: e.title },
      // Pas de traduction FR des notes : les traduire mécaniquement n'est pas
      // mon rôle, content-cli translate est fait pour ça. LocalizedText replie
      // sur EN en attendant.
      ...(e.notes?.trim() ? { note: { en: e.notes.trim() } } : {}),
      status: 'draft',
      sources: [url],
      // 5 décimales et non 1 : ces sources sont en lat/lng, dont l'amplitude
      // se compte en unités — au décimètre deux POI distincts se confondraient.
      processedFrom: identityKey(
        label,
        t.slug,
        needsCoordTiebreak ? `${e.id}@${worldDiscriminant(e.lat, e.lng, 5)}` : String(e.id),
      ),
    });
  }
  console.log(`${label.padEnd(16)} ${candidates.length} retenus, ${dropped} écartés`);
}

// --- 2. Jeux en coordonnées monde du jeu ---------------------------------
// L'image de carte est l'autorité sur ce qui est réellement cartographié : on
// lui demande si le pixel sous l'objet est de l'eau. Les jeux Mercator ne
// passent PAS ce filtre — les 30 déchets nucléaires sont volontairement immergés.
async function loadOceanProbe() {
  const dir = join(ROOT, 'NeonCompass', 'Resources', 'MapArt');
  // On sonde de préférence la variante d'origine : sa séparation eau/terre est
  // bien plus franche (bleu B=208 contre vert B=112) que celle de la restylée
  // (B ≤ 51 contre B ≥ 71), donc le test résiste mieux au downscale et à la
  // quantification. Les deux images sont géométriquement identiques.
  const classicPath = join(dir, 'island-classic.png');
  const styledPath = join(dir, 'island.png');
  const useClassic = existsSync(classicPath);
  const mapPath = useClassic ? classicPath : styledPath;
  if (!existsSync(mapPath)) {
    console.warn("! image de carte absente — filtre océan désactivé (lancer gtav-map.mjs d'abord)");
    return null;
  }
  const isOcean = useClassic ? isOceanRaw : isOceanNC;
  const { data, info } = await sharp(mapPath).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return (p) => {
    const x = Math.min(info.width - 1, Math.max(0, Math.round(p.x * info.width)));
    const y = Math.min(info.height - 1, Math.max(0, Math.round(p.y * info.height)));
    const i = (y * info.width + x) * info.channels;
    return isOcean(data[i], data[i + 1], data[i + 2]);
  };
}
const isOceanAt = await loadOceanProbe();

for (const set of WORLD_SETS) {
  const raw = JSON.parse(await fetchRetry(`${DUMPS}/${set.file}`));
  const entries = Array.isArray(raw) ? raw : Object.values(raw).flat();
  let kept = 0, dropped = 0;
  for (const e of entries) {
    const pos = set.pos ? set.pos(e) : (e.Position ?? e.position ?? e);
    const X = pos?.X ?? pos?.x, Y = pos?.Y ?? pos?.y;
    if (typeof X !== 'number' || typeof Y !== 'number') { dropped++; continue; }
    const p = worldToNorm(X, Y);
    // Hors bornes = hors de cette carte : North Yankton et Cayo Perico sont
    // dans les dumps mais pas sur cette image.
    if (!inBounds(p)) { dropped++; continue; }
    if (isOceanAt?.(p)) { dropped++; continue; }
    pois.push({
      category: set.category,
      collection: set.slug,
      position: { x: Number(p.x.toFixed(6)), y: Number(p.y.toFixed(6)) },
      title: set.title ? set.title(e) : { en: set.en, fr: set.fr },
      status: 'draft',
      sources: [`${DUMPS}/${set.file}`],
      // Coordonnées MONDE et non normalisées : recalibrer la projection ferait
      // bouger les secondes, donc changerait toutes les clés d'un coup. Le
      // `set.key` optionnel s'y ajoute quand la source porte un nom stable.
      processedFrom: identityKey(
        'DurtyFree',
        set.slug,
        [set.key?.(e), worldDiscriminant(X, Y)].filter(Boolean).join('@'),
      ),
    });
    kept++;
  }
  console.log(`${set.slug.padEnd(16)} ${kept} retenus, ${dropped} écartés`);
}

// --- 3. Réconciliation des identifiants ----------------------------------
// Les fichiers déjà écrits sont le registre : chacun porte sa clé d'identité
// dans `processedFrom`. On réutilise leur id, on n'en frappe que pour les clés
// inconnues. Une clé dupliquée dans ce run lève — voir gtav-poi-ids.mjs.
const { pois: deduped, dropped: duplicates } = dedupeIdenticalEntries(pois);
if (duplicates) console.log(`\ndoublons amont écartés : ${duplicates}`);

const existingIds = loadExisting(outDir);
const { pois: identified, reused, minted, orphaned } = reconcileIds(deduped, existingIds);
console.log(`\nidentifiants : ${reused} réutilisés, ${minted} frappés, ${orphaned.length} orphelins`);
for (const { key, id } of orphaned.slice(0, 10)) console.log(`  orphelin ${id}  (${key})`);
if (orphaned.length > 10) console.log(`  … et ${orphaned.length - 10} autres`);

// --- 4. Validation contre les schémas du projet --------------------------
// content-cli ne balaie que content/{poi,cheats,collections} ; on valide donc
// ici, avec le même schéma, pour que la fixture ne puisse pas dériver du format.
const ajv = new Ajv({ allErrors: true });
const validate = ajv.compile(JSON.parse(readFileSync(join(ROOT, 'content', 'schema', 'poi.schema.json'))));
let invalid = 0;
for (const p of identified) {
  if (!validate(p)) {
    invalid++;
    if (invalid <= 5) console.error(`FAIL ${p.id}: ${validate.errors.map((e) => `${e.instancePath} ${e.message}`).join('; ')}`);
  }
}
const ids = new Set(identified.map((p) => p.id));
if (ids.size !== identified.length) throw new Error(`ids dupliqués : ${identified.length - ids.size}`);
if (invalid) throw new Error(`${invalid} POI invalides au schéma`);

// Une collection référencée mais non déclarée donnerait des POI qui ne comptent
// dans aucun défi, sans que rien ne le signale — d'où l'échec dur.
const declared = new Set(
  readdirSync(join(ROOT, 'content', 'collections'))
    .filter((f) => f.endsWith('.json'))
    .map((f) => f.slice(0, -5)),
);
const undeclared = [...new Set(identified.map((p) => p.collection))].filter((c) => !declared.has(c));
if (undeclared.length) {
  throw new Error(`collections non déclarées dans content/collections : ${undeclared.join(', ')}`);
}
console.log(`validation : ${identified.length}/${identified.length} OK au schéma, ids uniques, collections déclarées`);

// --- 5. Écriture -----------------------------------------------------------
// On n'écrase que ce qu'on réémet. Les orphelins ne partent qu'avec --prune :
// un POI disparu de l'amont mérite un coup d'œil humain avant qu'on libère son
// id, parce qu'un id libéré peut être re-frappé pour une autre entité.
mkdirSync(outDir, { recursive: true });

// La liste à supprimer se calcule sur les FICHIERS, pas sur les clés orphelines :
// deux fichiers peuvent partager un même `processedFrom` (c'était le cas des 4
// collisions gta5-map suffixées `_2` par l'ancien pipeline), auquel cas un seul
// ressort comme orphelin et l'autre survivrait à la purge. Un fichier dont l'id
// n'est pas dans le run est périmé, point.
const liveIds = new Set(identified.map((p) => p.id));
const staleFiles = readdirSync(outDir).filter((f) => f.endsWith('.json') && !liveIds.has(f.slice(0, -5)));
if (doPrune && staleFiles.length) {
  for (const f of staleFiles) rmSync(join(outDir, f));
  console.log(`--prune : ${staleFiles.length} fichiers périmés supprimés`);
} else if (staleFiles.length) {
  console.log(`(${staleFiles.length} fichiers périmés conservés — relancer avec --prune pour les retirer)`);
}
for (const p of identified) writeFileSync(join(outDir, `${p.id}.json`), JSON.stringify(p, null, 2) + '\n');
console.log(`${identified.length} fichiers -> ${outDir}`);

// Le reste du script raisonne sur les POI identifiés.
pois.length = 0;
pois.push(...identified);

if (writeSeed) {
  // Le fixture embarqué ne porte que les champs que POI.swift décode ; status /
  // sources / processedFrom sont pipeline-only.
  const seed = pois.map(({ id, category, collection, position, title, note }) => ({
    id,
    category,
    collection,
    position,
    title,
    ...(note ? { note } : {}),
  }));
  const seedPath = join(ROOT, 'NeonCompass', 'Resources', 'POI', 'seed-poi.json');
  writeFileSync(seedPath, JSON.stringify(seed, null, 2) + '\n');
  const kb = (JSON.stringify(seed).length / 1024).toFixed(0);
  console.log(`seed-poi.json (${seed.length} POI, ${kb} Ko) -> ${seedPath}`);
}

const byCat = {};
for (const p of pois) byCat[p.category] = (byCat[p.category] ?? 0) + 1;
console.log('par catégorie :', byCat);

if (doRender) {
  const sharp = (await import('sharp')).default;
  const mapPath = join(ROOT, 'NeonCompass', 'Resources', 'MapArt', 'island.png');
  const { width } = await sharp(mapPath).metadata();
  const COLORS = { collectible: '#ff2fb9', activity: '#00e5ff', vehicle: '#c8ff00', landmark: '#ffffff', safehouse: '#ff8a00', event: '#7cffb2' };
  const dots = pois.map((p) =>
    `<circle cx="${(p.position.x * width).toFixed(1)}" cy="${(p.position.y * width).toFixed(1)}" r="${Math.max(3, width / 340)}" fill="${COLORS[p.category]}" stroke="#000" stroke-width="1.5"/>`).join('');
  const out = join(HERE, 'gtav-poi-check.png');
  await sharp(mapPath)
    .composite([{ input: Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${width}">${dots}</svg>`) }])
    .png().toFile(out);
  console.log(`contrôle visuel -> ${out}`);
}
