#!/usr/bin/env node
// Rend la carte de référence GTA V en une image plate unique + manifest, au
// même format que tile.js (l'app attend MapArt/island.png + manifest.json avec
// un champ `size`). Voir gtav-geo.mjs pour le géoréférencement et le pourquoi.
//
//   node gtav-map.mjs [--zoom 6] [--style atlas] [--pixels 4096] [--size 2048]
//                     [--colors 256] [--out DIR]
//
// Par défaut écrit dans NeonCompass/Resources/MapArt (donc dans l'app). Passer
// --out ailleurs pour garder la carte hors du binaire.
//
// Zooms sources disponibles : z3 (768 px) à z7 (12 288 px). z6 = 6 144 px /
// 576 tuiles alimente un rendu à 4 096 px avec de la marge, sans télécharger
// les 2 304 tuiles de z7.

import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import sharp from 'sharp';
import {
  TILE, TILE_BASE, STYLES, MIN_ZOOM, MAX_ZOOM, FRACTION, gridFor, fetchRetry, pool,
} from './gtav-geo.mjs';
import { restyle } from './gtav-restyle.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}

const zoom = Number(arg('zoom', 6));
const style = arg('style', 'atlas');
// `size` = espace de coordonnées de contenu, écrit dans le manifest et lu par
// MapGeometry. `pixels` = résolution réelle du PNG. Les deux sont découplés
// exprès : l'image est sur-échantillonnée par rapport au contenu, ce qui est
// le seul levier contre le flou au zoom maximal. À zoom 2,5 sur un écran @3x,
// la carte est demandée à 2048 × 2,5 × 3 = 15 360 px ; aucune image
// embarquable n'y répond, mais 2× de sur-échantillonnage ramène le facteur
// d'agrandissement de 7,5× à 3,75×. Au-delà, 8 192 px coûterait 256 Mo une
// fois décodé : c'est le mur, et le seul moyen de le franchir est une
// pyramide de tuiles.
const size = Number(arg('size', 2048));
const pixels = Number(arg('pixels', 4096));
// 128 couleurs produisaient un grain de tramage visible dès qu'on zoomait.
// 256 le fait disparaître pour ~2× le poids ; le sans-palette coûte 4× de plus
// sans gain perceptible sur une carte en aplats.
const colors = Number(arg('colors', 256));
const outDir = arg('out', join(ROOT, 'NeonCompass', 'Resources', 'MapArt'));

if (!STYLES.includes(style)) throw new Error(`--style doit être ${STYLES.join('|')}`);
if (!(zoom >= MIN_ZOOM && zoom <= MAX_ZOOM)) throw new Error(`--zoom entre ${MIN_ZOOM} et ${MAX_ZOOM}`);

const grid = gridFor(zoom);
const full = grid * TILE;
console.log(`GTA V ${style} z${zoom} — ${grid}×${grid} tuiles (${full}px) -> ${pixels}px, contenu ${size}, ${colors || 'sans'} couleurs`);

const coords = [];
for (let y = 0; y < grid; y++) for (let x = 0; x < grid; x++) coords.push({ x, y });

const tiles = await pool(
  coords.map(({ x, y }) => async () => {
    try {
      return { input: await fetchRetry(`${TILE_BASE}/${style}/${zoom}-${x}_${y}.png`, { asBuffer: true }),
               left: x * TILE, top: y * TILE };
    } catch {
      return null; // tuile de bord absente : le fond océan la couvre
    }
  }),
  12,
  (d, t) => { if (d % 24 === 0 || d === t) process.stdout.write(`\r  ${d}/${t} tuiles`); }
);
console.log();

const present = tiles.filter(Boolean);
if (present.length === 0) throw new Error('aucune tuile récupérée');

// L'image de carte ne remplit pas tout le carré de tuiles (son bord droit et
// son bord bas tombent en milieu de dernière tuile) : le reste est
// transparent. On ne recadre PAS — recadrer changerait l'échelle et
// désalignerait les constantes de gtav-geo.mjs. On remplit donc la marge avec
// la couleur d'océan échantillonnée sur la carte elle-même, pour qu'elle passe
// pour de l'eau au lieu d'un trou.
const stitched = await sharp({ create: { width: full, height: full, channels: 4, background: '#00000000' } })
  .composite(present).png().toBuffer();

const corner = await sharp(stitched).extract({ left: 2, top: 2, width: 1, height: 1 }).raw().toBuffer();
const ocean = { r: corner[0], g: corner[1], b: corner[2], alpha: 1 };
console.log(`  fond océan échantillonné : rgb(${ocean.r},${ocean.g},${ocean.b})`);

mkdirSync(outDir, { recursive: true });

const { data: rawRgb, info } = await sharp(stitched)
  .flatten({ background: ocean })
  .removeAlpha()
  .raw()
  .toBuffer({ resolveWithObject: true });

// `palette` quantifie en couleurs indexées — la carte est en aplats, donc la
// perte reste invisible et le fichier bien plus léger (l'app embarque ces
// images, les garder bornées compte). Mesuré à 3 072 px : 678 Ko à 128
// couleurs, 1 220 Ko à 256, 3 146 Ko sans palette. À 4 096 px : 2 016 Ko à 256.
async function encode(rgb, filename) {
  const buf = await sharp(rgb, { raw: { width: info.width, height: info.height, channels: 3 } })
    .resize(pixels, pixels, { fit: 'fill', kernel: 'lanczos3' })
    .png({ palette: colors > 0, effort: 9, ...(colors > 0 ? { colors } : {}) })
    .toBuffer();
  writeFileSync(join(outDir, filename), buf);
  console.log(`  ${filename.padEnd(20)} ${(buf.length / 1024).toFixed(0)} Ko`);
  return buf;
}

// Les deux variantes sortent du MÊME assemblage de tuiles : elles sont donc
// géométriquement identiques par construction, et un seul jeu de constantes
// de géoréférencement vaut pour les deux. Les régénérer séparément
// autoriserait une dérive silencieuse entre elles.
const classic = await encode(rawRgb, 'island-classic.png');

// Restylage AVANT tout redimensionnement : classer les aplats est fiable à la
// résolution source, beaucoup moins après un downscale qui interpole les
// teintes entre classes voisines.
const styled = restyle(rawRgb, info.width, info.height);
console.log(`  restylage Neon Compass — ${styled.stats}  (${styled.colors} couleurs source)`);
const image = await encode(styled.data, 'island.png');

writeFileSync(
  join(outDir, 'manifest.json'),
  JSON.stringify({
    size,
    source: `gtav:${style}:z${zoom}`,
    sourceSha256: createHash('sha256').update(image).digest('hex').slice(0, 16),
    classicSha256: createHash('sha256').update(classic).digest('hex').slice(0, 16),
    // Résolution réelle des PNG — supérieure à `size` (espace de contenu) pour
    // limiter le flou au zoom maximal.
    pixels,
    // Rejoués par gtav-poi.mjs : si ces valeurs ne correspondent pas à celles
    // de gtav-geo.mjs, l'image et les pins ne viennent pas du même import.
    fraction: FRACTION,
    tiles: `${grid}x${grid}`,
  }, null, 2) + '\n'
);

console.log(`  ${present.length}/${coords.length} tuiles présentes`);
