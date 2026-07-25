#!/usr/bin/env node
// Importe les POI de la carte de référence GTA V au schéma content/schema/
// poi.schema.json, et régénère le fixture embarqué que l'app lit réellement
// (Resources/POI/seed-poi.json — cf. POILoader.loadSeed).
//
//   node gtav-poi.mjs [--out content/poi-gtav] [--no-seed] [--render]
//
// Les POI atterrissent dans content/poi-gtav/ et NON dans content/poi/ : ce
// dernier porte le contenu éditorial GTA VI qui part vers Firestore, et
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

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}
const outDir = arg('out', join(ROOT, 'content', 'poi-gtav'));
const writeSeed = !process.argv.includes('--no-seed');
const doRender = process.argv.includes('--render');

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
  },
];

// Les id source ne sont pas fiables : gta5-map réutilise 4 id pour des entrées
// distinctes. On garde l'id source (stable si l'amont n'est pas réordonné) et
// on suffixe seulement en cas de collision réelle.
const usedIds = new Set();
function uniqueId(base) {
  if (!usedIds.has(base)) { usedIds.add(base); return base; }
  for (let n = 2; ; n++) {
    const candidate = `${base}_${n}`;
    if (!usedIds.has(candidate)) { usedIds.add(candidate); return candidate; }
  }
}

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
  let kept = 0, dropped = 0;
  for (const e of entries) {
    const t = TYPES[e.type];
    if (!t) { dropped++; continue; }
    const p = mercatorToNorm(e.lat, e.lng);
    // Le jeu danharper contient un marqueur parasite hors carte, laissé par le
    // handler de clic-droit de l'auteur.
    if (!inBounds(p)) { dropped++; continue; }
    const fr = frTitle(e.title, e.type, t.fr);
    pois.push({
      id: uniqueId(`poi_gtav_${t.slug}_${e.id}`),
      category: t.category,
      position: { x: Number(p.x.toFixed(6)), y: Number(p.y.toFixed(6)) },
      title: fr ? { en: e.title, fr } : { en: e.title },
      // Pas de traduction FR des notes : les traduire mécaniquement n'est pas
      // mon rôle, content-cli translate est fait pour ça. LocalizedText replie
      // sur EN en attendant.
      ...(e.notes?.trim() ? { note: { en: e.notes.trim() } } : {}),
      status: 'draft',
      sources: [url],
      processedFrom: `${label}#${e.id}`,
    });
    kept++;
  }
  console.log(`${label.padEnd(16)} ${kept} retenus, ${dropped} écartés`);
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
  for (const [i, e] of entries.entries()) {
    const pos = set.pos ? set.pos(e) : (e.Position ?? e.position ?? e);
    const X = pos?.X ?? pos?.x, Y = pos?.Y ?? pos?.y;
    if (typeof X !== 'number' || typeof Y !== 'number') { dropped++; continue; }
    const p = worldToNorm(X, Y);
    // Hors bornes = hors de cette carte : North Yankton et Cayo Perico sont
    // dans les dumps mais pas sur cette image.
    if (!inBounds(p)) { dropped++; continue; }
    if (isOceanAt?.(p)) { dropped++; continue; }
    pois.push({
      id: uniqueId(`poi_gtav_${set.slug}_${i}`),
      category: set.category,
      position: { x: Number(p.x.toFixed(6)), y: Number(p.y.toFixed(6)) },
      title: set.title ? set.title(e) : { en: set.en, fr: set.fr },
      status: 'draft',
      sources: [`${DUMPS}/${set.file}`],
      processedFrom: `DurtyFree:${set.slug}#${i}`,
    });
    kept++;
  }
  console.log(`${set.slug.padEnd(16)} ${kept} retenus, ${dropped} écartés`);
}

// --- 3. Validation contre le schéma du projet ----------------------------
// content-cli ne balaie que content/poi ; on valide donc ici, avec le même
// schéma, pour que la fixture ne puisse pas dériver du format.
const ajv = new Ajv({ allErrors: true });
const validate = ajv.compile(JSON.parse(readFileSync(join(ROOT, 'content', 'schema', 'poi.schema.json'))));
let invalid = 0;
for (const p of pois) {
  if (!validate(p)) {
    invalid++;
    if (invalid <= 5) console.error(`FAIL ${p.id}: ${validate.errors.map((e) => `${e.instancePath} ${e.message}`).join('; ')}`);
  }
}
const ids = new Set(pois.map((p) => p.id));
if (ids.size !== pois.length) throw new Error(`ids dupliqués : ${pois.length - ids.size}`);
if (invalid) throw new Error(`${invalid} POI invalides au schéma`);
console.log(`\nvalidation : ${pois.length}/${pois.length} OK au schéma, ids uniques`);

// --- 4. Écriture -----------------------------------------------------------
// Purge d'abord : sans ça un import plus étroit laisserait derrière lui les
// fichiers du précédent, plus large.
if (existsSync(outDir)) {
  for (const f of readdirSync(outDir).filter((f) => f.startsWith('poi_gtav_') && f.endsWith('.json'))) {
    rmSync(join(outDir, f));
  }
}
mkdirSync(outDir, { recursive: true });
for (const p of pois) writeFileSync(join(outDir, `${p.id}.json`), JSON.stringify(p, null, 2) + '\n');
console.log(`${pois.length} fichiers -> ${outDir}`);

if (writeSeed) {
  // Le fixture embarqué ne porte que les champs que POI.swift décode ; status /
  // sources / processedFrom sont pipeline-only.
  const seed = pois.map(({ id, category, position, title, note }) =>
    note ? { id, category, position, title, note } : { id, category, position, title });
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
