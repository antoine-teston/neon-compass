#!/usr/bin/env node
// Rend la carte communautaire GTA VI (State of Leonida, auteur YANIS v14) en
// une image plate unique. Depuis la tâche 8, ne produit plus de manifest —
// contrairement à gtav-map.mjs, qui en écrit toujours un pour GTA V.
//
//   node gtavi-map.mjs [--zoom 5] [--style normal] [--pixels 4096]
//                      [--colors 256] [--out DIR] [--restyle]
//
// Zooms disponibles : z0 à z6. z5 = 8 192 px / 1 024 tuiles de 256 px —
// résolution suffisante pour un rendu à 4 096 px.
//
// Source : https://map.stateofleonida.net — carte communautaire YANIS v14.

import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { eraseAndDash, gridProbe, gridCenters, gridAndStyle } from './gtavi-transform.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

const TILE = 256;
const TILE_BASE = 'https://map.stateofleonida.net/tiles';
const MAP_AUTHOR = 'YANIS';
const MAP_VERSION = 'v14';
const STYLES = ['normal', 'dark'];
const MIN_ZOOM = 0;
const MAX_ZOOM = 6;

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}
const flag = (name) => process.argv.includes(`--${name}`);

const zoom = Number(arg('zoom', 5));
const style = arg('style', 'normal');
const pixels = Number(arg('pixels', 8192));
const colors = Number(arg('colors', 256));
const doRestyle = flag('restyle');
// Ce script ne produit PLUS les fichiers embarqués : depuis le pavage z6,
// `MapArt/island-vi*.png` sont les socles de 4 096 px que `gtavi-tiles.mjs`
// découpe en même temps que la pyramide. `gtavi-map.mjs` ne sert plus que de
// référence de non-régression pour `gtavi-transform.mjs`. Sa sortie va donc
// dans `out/`, et il faut un `--out` explicite pour viser autre chose —
// sinon un `node gtavi-map.mjs --restyle --classic` lancé par réflexe
// écraserait les socles par du z5 à 8 192 px, désaccordé de la pyramide, et
// rien dans le code ne s'y opposerait.
const outDir = arg('out', join(HERE, 'out'));

if (!STYLES.includes(style)) throw new Error(`--style doit être ${STYLES.join('|')}`);
if (!(zoom >= MIN_ZOOM && zoom <= MAX_ZOOM)) throw new Error(`--zoom entre ${MIN_ZOOM} et ${MAX_ZOOM}`);

// Le grid YANIS dépasse 2^z — sonder le serveur pour trouver les vraies bornes.
async function probeGrid(z) {
  const base = `${TILE_BASE}/${MAP_AUTHOR}/${MAP_VERSION}/${style}/${z}`;
  const mid = Math.floor(2 ** z / 2);
  async function maxCoord(axis) {
    let hi = 2 ** z - 1;
    for (let c = hi + 1; c < hi + 20; c++) {
      const url = axis === 'x' ? `${base}/${c}/${mid}.png` : `${base}/${mid}/${c}.png`;
      try { const r = await fetch(url, { method: 'HEAD' }); if (!r.ok) break; hi = c; } catch { break; }
    }
    return hi + 1;
  }
  const [gx, gy] = await Promise.all([maxCoord('x'), maxCoord('y')]);
  return { gx, gy };
}
const { gx: gridX, gy: gridY } = await probeGrid(zoom);
console.log(`GTA VI ${MAP_AUTHOR}/${MAP_VERSION} ${style} z${zoom} — ${gridX}×${gridY} tuiles (${gridX * TILE}×${gridY * TILE}px) -> ${pixels}px, ${colors || 'sans'} couleurs`);

async function fetchRetry(url, { tries = 4 } = {}) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return Buffer.from(await r.arrayBuffer());
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 250 * 2 ** i));
    }
  }
  throw new Error(`${url}: ${lastErr.message}`);
}

async function pool(jobs, limit, onDone) {
  const results = new Array(jobs.length);
  let next = 0;
  let done = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, jobs.length) }, async () => {
      while (next < jobs.length) {
        const i = next++;
        results[i] = await jobs[i]();
        onDone?.(++done, jobs.length);
      }
    })
  );
  return results;
}

const coords = [];
for (let y = 0; y < gridY; y++) for (let x = 0; x < gridX; x++) coords.push({ x, y });

const tiles = await pool(
  coords.map(({ x, y }) => async () => {
    try {
      return {
        input: await fetchRetry(
          `${TILE_BASE}/${MAP_AUTHOR}/${MAP_VERSION}/${style}/${zoom}/${x}/${y}.png`,
        ),
        left: x * TILE,
        top: y * TILE,
      };
    } catch {
      return null;
    }
  }),
  12,
  (d, t) => { if (d % 48 === 0 || d === t) process.stdout.write(`\r  ${d}/${t} tuiles`); }
);
console.log();

const present = tiles.filter(Boolean);
if (present.length === 0) throw new Error('aucune tuile récupérée');

mkdirSync(outDir, { recursive: true });

// Échantillonner l'océan au centre de la tuile (0,0) — toujours de l'eau.
const cornerTile = present.find(t => t.left === 0 && t.top === 0) ?? present[0];
const corner = await sharp(cornerTile.input)
  .extract({ left: 100, top: 100, width: 1, height: 1 }).raw().toBuffer();
const ocean = { r: corner[0], g: corner[1], b: corner[2], alpha: 1 };
console.log(`  fond océan échantillonné : rgb(${ocean.r},${ocean.g},${ocean.b})`);

const fullW = gridX * TILE, fullH = gridY * TILE;
const stitched = await sharp({
  create: { width: fullW, height: fullH, channels: 4, background: '#00000000' },
}).composite(present).png().toBuffer();

const { data: rawRgb, info } = await sharp(stitched)
  .flatten({ background: ocean })
  .removeAlpha()
  .raw()
  .toBuffer({ resolveWithObject: true });


async function encode(rgb, filename) {
  const buf = await sharp(rgb, { raw: { width: info.width, height: info.height, channels: 3 } })
    .resize(pixels, pixels, { fit: 'fill', kernel: 'lanczos3' })
    .png({ palette: colors > 0, effort: 9, ...(colors > 0 ? { colors } : {}) })
    .toBuffer();
  writeFileSync(join(outDir, filename), buf);
  console.log(`  ${filename.padEnd(24)} ${(buf.length / 1024).toFixed(0)} Ko`);
  return buf;
}

const full = { w: info.width, h: info.height };
const whole = { x: 0, y: 0, w: full.w, h: full.h };
// Copie des pixels source pour la version classic (re-synchronisée sur
// l'effacement du panneau par eraseAndDash, voir plus bas).
const classicRgb = flag('classic') ? Buffer.from(rawRgb) : null;

// Le traitement vit dans gtavi-transform.mjs, fenêtrable et paramétré en
// échelle. Ici on en prend le cas dégénéré : une fenêtre qui est l'image
// entière, un cœur qui est l'image entière, un facteur d'échelle qui vaut 1.
if (doRestyle) {
  const W = info.width, H = info.height;

  // La classic reprend l'effacement (couleur océan réelle) mais pas le reste :
  // la grille de coordonnées ET les limites de comté font partie de la source
  // qu'elle restitue. La copie se prend donc DANS eraseAndDash, entre ses deux
  // moitiés — la reprendre après coup y emporterait la suppression des tirets,
  // ce que la comparaison octet pour octet de island-vi-classic.png a tranché.
  const a = eraseAndDash(rawRgb, whole, full, ocean, whole, classicRgb);
  console.log(`  légende : ${a.erased} pixels → océan`);
  console.log(`  comtés : ${a.dashCompsInWindow} tirets alignés, ${a.dashSuppressed} px → voisin`);

  const probe = gridProbe(rawRgb, whole, full, whole);
  const centers = gridCenters(probe.colHits, probe.rowHits, full);
  console.log(`  grille : ${centers.nCols} colonnes + ${centers.nRows} lignes détectées sur l'océan`);

  const styled = gridAndStyle(rawRgb, whole, full, whole, centers);
  console.log(`  grille : ${styled.gridTotal} détectés, ${styled.gridSuppressed} → voisin`);
  console.log(`  restylage Neon Compass — ${styled.stats}  (${styled.colorsInWindow} couleurs source, ${styled.labelUnified} px de libellés unifiés, ${styled.gridErased} axes fins, ${styled.oceanCleaned} isolés océan)`);
  console.log(`  océan aplati : ${styled.flattened} pixels → NIGHT_SKY exact (gradient préservé)`);

  // Recadrer sur l'île. La boîte englobante est relevée par le traitement, qui
  // exclut du scan les zones d'effacement (panneau, labels) pour éviter les
  // faux bords créés par la dilatation du trait de côte.
  const { minX: bMinX, maxX: bMaxX, minY: bMinY, maxY: bMaxY } = styled.bbox;
  const NS = [0x0A, 0x08, 0x1A];   // NIGHT_SKY, fond du cadre élargi
  // La plus grande marge qui garde nord et sud SYMÉTRIQUES. Le carré force le
  // crop contre le bord droit de la source, ce qui écrasait la marge verticale
  // à 80 px — 19 pt à l'écran, sept fois moins qu'à l'est, et pas de quoi
  // amener au centre une épingle posée sur la côte nord ou sud.
  const margin = Math.min(bMinY, H - 1 - bMaxY);   // 468 sur la source actuelle
  let cropX = Math.max(0, bMinX - margin);
  const cropY = Math.max(0, bMinY - margin);
  let cropW = Math.min(W, bMaxX + margin + 1) - cropX;
  const cropH = Math.min(H, bMaxY + margin + 1) - cropY;
  // Marge d'océan ouest/est pour la navigation : le cadrage est élargi en
  // CARRÉ (cropW = cropH), centré sur l'île et borné par la source. Le resize
  // fit:contain n'a alors plus de bandes de fond — tout le cadre est de
  // l'océan réel — et la classic partage le même cadrage, donc les deux
  // cartes sont dimensionnellement identiques in-app.
  if (cropW < cropH && cropH <= W) {
    let left = cropX - ((cropH - cropW) >> 1);
    left = Math.max(0, Math.min(left, W - cropH));
    cropX = left;
    cropW = cropH;
  }
  console.log(`  île : x=${bMinX}..${bMaxX} y=${bMinY}..${bMaxY} → crop ${cropW}×${cropH} (océan ouest ${bMinX - cropX}px / est ${cropX + cropW - 1 - bMaxX}px)`);

  const resized = await sharp(styled.data, { raw: { width: W, height: H, channels: 3 } })
    .extract({ left: cropX, top: cropY, width: cropW, height: cropH })
    .resize(pixels, pixels, { fit: 'contain', kernel: 'lanczos3', background: { r: NS[0], g: NS[1], b: NS[2] } })
    .flatten({ background: { r: NS[0], g: NS[1], b: NS[2] } })
    .sharpen({ sigma: 1, m1: 0.6, m2: 2 })
    .raw()
    .toBuffer();
  const cleanBuf = await sharp(resized, { raw: { width: pixels, height: pixels, channels: 3 } })
    .png({ palette: colors > 0, effort: 9, ...(colors > 0 ? { colors } : {}) })
    .toBuffer();
  writeFileSync(join(outDir, 'island-vi.png'), cleanBuf);
  console.log(`  island-vi.png (nettoyé)    ${(cleanBuf.length / 1024).toFixed(0)} Ko`);

  // Version classic : même cadrage que le Neon, mais couleurs source.
  if (classicRgb) {
    const classicBuf = await sharp(classicRgb, { raw: { width: W, height: H, channels: 3 } })
      .extract({ left: cropX, top: cropY, width: cropW, height: cropH })
      .resize(pixels, pixels, { fit: 'contain', kernel: 'lanczos3', background: ocean })
      .flatten({ background: ocean })
      .png({ effort: 9 })
      .toBuffer();
    writeFileSync(join(outDir, 'island-vi-classic.png'), classicBuf);
    console.log(`  island-vi-classic.png      ${(classicBuf.length / 1024).toFixed(0)} Ko`);
  }
} else {
  await encode(rawRgb, 'island-vi.png');
  console.log('  (--restyle non passé, island-vi.png = classique)');
}

console.log(`  ${present.length}/${coords.length} tuiles présentes`);
