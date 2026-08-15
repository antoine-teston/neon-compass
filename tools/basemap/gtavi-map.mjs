#!/usr/bin/env node
// Rend la carte communautaire GTA VI (State of Leonida, auteur YANIS v14) en
// une image plate unique + manifest, au même format que gtav-map.mjs.
//
//   node gtavi-map.mjs [--zoom 5] [--style normal] [--pixels 4096] [--size 2048]
//                      [--colors 256] [--out DIR] [--restyle]
//
// Zooms disponibles : z0 à z6. z5 = 8 192 px / 1 024 tuiles de 256 px —
// résolution suffisante pour un rendu à 4 096 px.
//
// Source : https://map.stateofleonida.net — carte communautaire YANIS v14.

import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { restyle } from './gtavi-restyle.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');

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
const size = Number(arg('size', 2048));
const pixels = Number(arg('pixels', 8192));
const colors = Number(arg('colors', 256));
const doRestyle = flag('restyle');
const outDir = arg('out', join(ROOT, 'NeonCompass', 'Resources', 'MapArt'));

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
const full = Math.max(gridX, gridY) * TILE;
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

// Copie des pixels source pour la version classic (re-synchronisée après
// l'effacement du panneau, voir plus bas).
const classicRgb = flag('classic') ? Buffer.from(rawRgb) : null;

let image;
if (doRestyle) {
  // Effacer le panneau de légende AVANT le restylage.
  // Le panneau (titre YANIS, légende, crédits, photos) est incrusté dans les
  // tuiles source avec un fond BLANC OPAQUE — il n'y a aucun contenu
  // géographique visible sous le panneau. On remplace TOUT pixel non-océan
  // dans la zone du panneau (profil mesuré) par la couleur océan.
  const W = info.width;
  // L'océan réel sert de couleur d'effacement : classify() le reconnaît
  // désormais (b>130 && b>r+50 && r<100 && g<160 → WATER), et il tombe sur le
  // MÊME palier de dégradé que l'océan profond voisin. Le crop élargi vers
  // l'ouest peut donc inclure la zone effacée sans couture visible, dans le
  // rendu néon comme dans la version classic.
  const [oR, oG, oB] = [ocean.r, ocean.g, ocean.b];


  const H = info.height;
  let erased = 0;

  // Panneau gauche (x < 3000, couvre tout le panneau YANIS + marge).
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < 3000 && x < W; x++) {
      const o = (y * W + x) * 3;
      rawRgb[o] = oR; rawRgb[o + 1] = oG; rawRgb[o + 2] = oB;
      erased++;
    }
  }
  // Labels de grille rouges — bandes larges sur les 3 autres bords
  for (let y = 0; y < 400; y++) {
    for (let x = 3000; x < W; x++) {
      const o = (y * W + x) * 3;
      rawRgb[o] = oR; rawRgb[o + 1] = oG; rawRgb[o + 2] = oB;
      erased++;
    }
  }
  for (let y = H - 400; y < H; y++) {
    for (let x = 3000; x < W; x++) {
      const o = (y * W + x) * 3;
      rawRgb[o] = oR; rawRgb[o + 1] = oG; rawRgb[o + 2] = oB;
      erased++;
    }
  }
  for (let y = 400; y < H - 400; y++) {
    for (let x = W - 500; x < W; x++) {
      const o = (y * W + x) * 3;
      rawRgb[o] = oR; rawRgb[o + 1] = oG; rawRgb[o + 2] = oB;
      erased++;
    }
  }
  console.log(`  légende : ${erased} pixels → océan`);

  // La version classic reprend l'effacement (couleur océan réelle) : le crop
  // élargi vers l'ouest inclut l'ancienne zone du panneau YANIS. La grille de
  // coordonnées, elle, reste dans la classic — elle fait partie de la source.
  if (classicRgb) classicRgb.set(rawRgb);

  // Limites de comté : lignes droites en TIRETS rose pur (rgb ~238,100,100,
  // LEONARD/VICE-DALE) ou rouge-orangé (rgb ~224,96,64, AMBROSIA/KELLY).
  // Le rose des tirets est la couleur exacte du texte de quartier
  // (rgb ~240,110,100) : aucune couleur ne les sépare. La géométrie tranche
  // en trois temps. Un tiret est un composant FIN (épaisseur ≤12 px, mesurée
  // par les moments d'ordre 2, donc valable à toute orientation) et allongé ;
  // il est ALIGNÉ sur ≥2 autres tirets le long de son propre axe majeur.
  // Le « I » d'un nom de quartier est fin lui aussi, mais ses voisins
  // (B, O, H…) ne sont pas des tirets et ne sont pas dans son axe ; les
  // autoroutes rouge vif (Overseas Highway des Keys) et les routes roses
  // forment des composants géants exclus par l'aire.
  const isWarm = (o) => rawRgb[o] > 170 && rawRgb[o] - rawRgb[o + 1] >= 70 && rawRgb[o] - rawRgb[o + 2] >= 70;
  const dashSeen = new Uint8Array(W * H);
  const dashes = [];
  const dStack = [];
  for (let y = 3; y < H - 3; y++) {
    for (let x = 3005; x < W - 3; x++) {
      const i0 = y * W + x;
      if (dashSeen[i0] || !isWarm(i0 * 3)) continue;
      dStack.length = 0;
      dStack.push(i0); dashSeen[i0] = 1;
      // Le BFS consomme TOUT le composant même s'il dépasse le plafond —
      // interrompre laisserait le reste d'une autoroute géante repartir en
      // fragments de la taille d'un tiret au balayage suivant.
      const comp = [];
      let area = 0, sx = 0, sy = 0;
      while (dStack.length > 0) {
        const i = dStack.pop();
        area++;
        if (comp.length <= 1500) comp.push(i);
        const px = i % W, py = (i / W) | 0;
        sx += px; sy += py;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (!dx && !dy) continue;
            const nx = px + dx, ny = py + dy;
            if (nx < 3 || nx >= W - 3 || ny < 3 || ny >= H - 3) continue;
            const j = ny * W + nx;
            if (!dashSeen[j] && isWarm(j * 3)) { dashSeen[j] = 1; dStack.push(j); }
          }
        }
      }
      if (area < 30 || area > 1500) continue;
      const cx = sx / comp.length, cy = sy / comp.length;
      let mxx = 0, myy = 0, mxy = 0;
      for (const i of comp) {
        const dx = (i % W) - cx, dy = ((i / W) | 0) - cy;
        mxx += dx * dx; myy += dy * dy; mxy += dx * dy;
      }
      mxx /= comp.length; myy /= comp.length; mxy /= comp.length;
      const tr = mxx + myy, det = Math.sqrt((mxx - myy) ** 2 + 4 * mxy * mxy);
      const l1 = (tr + det) / 2, l2 = (tr - det) / 2;
      if (Math.sqrt(12 * Math.max(0, l2)) > 12 || l2 / l1 > 0.25) continue;
      const theta = 0.5 * Math.atan2(2 * mxy, mxx - myy);
      dashes.push({ cx, cy, ux: Math.cos(theta), uy: Math.sin(theta), comp });
    }
  }
  // Confirmation en deux temps : ≥2 voisins colinéaires, puis PROPAGATION.
  // Un tiret de bout de ligne n'a qu'un seul voisin dans les 130 px (la ligne
  // s'arrête là), mais si ce voisin est lui-même confirmé, le tiret appartient
  // à la même limite — itéré jusqu'au point fixe, sinon chaque extrémité de
  // ligne laisse un orphelin que l'uniformisation des libellés repeint en blanc.
  const collinear = (d, e) => {
    const vx = e.cx - d.cx, vy = e.cy - d.cy;
    if (Math.hypot(vx, vy) > 130) return false;
    if (Math.abs(vx * -d.uy + vy * d.ux) > 9) return false;
    return Math.abs(d.ux * e.ux + d.uy * e.uy) >= 0.9;
  };
  const confirmed = new Uint8Array(dashes.length);
  for (let a = 0; a < dashes.length; a++) {
    let neighbors = 0;
    for (let b = 0; b < dashes.length && neighbors < 2; b++) {
      if (b !== a && collinear(dashes[a], dashes[b])) neighbors++;
    }
    if (neighbors >= 2) confirmed[a] = 1;
  }
  for (let changed = true; changed;) {
    changed = false;
    for (let a = 0; a < dashes.length; a++) {
      if (confirmed[a]) continue;
      for (let b = 0; b < dashes.length; b++) {
        if (b !== a && confirmed[b] && collinear(dashes[a], dashes[b])) {
          confirmed[a] = 1;
          changed = true;
          break;
        }
      }
    }
  }
  const dashPx = new Uint8Array(W * H);
  let dashComps = 0, dashTotal = 0;
  for (let a = 0; a < dashes.length; a++) {
    if (!confirmed[a]) continue;
    const d = dashes[a];
    dashComps++;
    for (const i of d.comp) {
      const px = i % W, py = (i / W) | 0;
      // Le tiret plus son halo d'anticrénelage (mélange chaud rose/orangé sur
      // fond vert ou gris, qui laisserait un fantôme du tiret sinon).
      for (let dy = -2; dy <= 2; dy++) {
        for (let dx = -2; dx <= 2; dx++) {
          const j = (py + dy) * W + px + dx;
          if (dashPx[j]) continue;
          const jo = j * 3;
          if ((dx === 0 && dy === 0) || (rawRgb[jo] >= 120 && rawRgb[jo] - rawRgb[jo + 1] >= 25)) {
            dashPx[j] = 1;
            dashTotal++;
          }
        }
      }
    }
  }
  // La source de remplacement ne doit être ni chaude (le composant côtier
  // géant, jamais effacé, frôle certains tirets) ni « matière à libellé » au
  // sens des familles de l'uniformisation (gtavi-restyle.mjs) : le mélange
  // vert pâle de l'anticrénelage tiret-sur-terre (~204,222,196) passe le test
  // de la famille pâle, et le dupliquer sur la largeur du tiret fabrique un
  // composant assez grand pour être repeint en blanc-lavande.
  const isLabelish = (o) => {
    const r = rawRgb[o], g = rawRgb[o + 1], b = rawRgb[o + 2];
    if (r > 210 && r - g > 110) return true;
    const l = (r + g + b) / 3, s = Math.max(r, g, b) - Math.min(r, g, b);
    return l > 195 && s >= 13 && s <= 45 && g >= r && r > b;
  };
  let dashSuppressed = 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      if (!dashPx[i]) continue;
      let bestDist = 20, bestI = -1;
      for (const [dy, dx] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
        for (let d = 1; d <= 15; d++) {
          const nx = x + dx * d, ny = y + dy * d;
          if (nx < 0 || nx >= W || ny < 0 || ny >= H) break;
          const j = ny * W + nx;
          if (!dashPx[j] && !isWarm(j * 3) && !isLabelish(j * 3)) {
            if (d < bestDist) { bestDist = d; bestI = j; }
            break;
          }
        }
      }
      if (bestI >= 0) {
        const o = i * 3, so = bestI * 3;
        rawRgb[o] = rawRgb[so]; rawRgb[o + 1] = rawRgb[so + 1]; rawRgb[o + 2] = rawRgb[so + 2];
        dashSuppressed++;
      }
    }
  }
  console.log(`  comtés : ${dashComps} tirets alignés, ${dashSuppressed} px → voisin`);

  // Grille de coordonnées : traits rouge terne rgb(~156-182,~84,~84) — la MÊME
  // famille de rouge que les autoroutes (r-g 60-96 des deux côtés). Aucun seuil
  // de couleur ne les sépare : une détection par couleur seule amputait tout le
  // réseau routier. La différence est géométrique : la grille est faite de
  // colonnes/lignes parfaitement axiales qui traversent l'océan en
  // l'assombrissant (rgb ~47,95,141 contre 44,103,164 pur). On sonde l'océan
  // pur pour localiser les traits, puis on n'efface QUE dans ces bandes —
  // une route qui croise une bande est restaurée par son voisin hors bande.
  const dPure = (r, g, b) => (r - 44) ** 2 + (g - 103) ** 2 + (b - 164) ** 2;
  const dDark = (r, g, b) => (r - 47) ** 2 + (g - 95) ** 2 + (b - 141) ** 2;
  const isDarkened = (r, g, b) => dDark(r, g, b) < dPure(r, g, b) && dPure(r, g, b) > 150 && dDark(r, g, b) < 400;

  // Océan pur au nord (l'île commence vers y≈1000) et à l'ouest (x≈3400).
  const PY0 = 420, PY1 = 980, PX0 = 3005, PX1 = 3400;
  const colHits = new Uint32Array(W), rowHits = new Uint32Array(H);
  for (let y = PY0; y < PY1; y++) {
    for (let x = 3005; x < W - 505; x++) {
      const o = (y * W + x) * 3;
      if (isDarkened(rawRgb[o], rawRgb[o + 1], rawRgb[o + 2])) colHits[x]++;
    }
  }
  for (let y = 405; y < H - 405; y++) {
    for (let x = PX0; x < PX1; x++) {
      const o = (y * W + x) * 3;
      if (isDarkened(rawRgb[o], rawRgb[o + 1], rawRgb[o + 2])) rowHits[y]++;
    }
  }
  const colCenter = new Int32Array(W).fill(-1), rowCenter = new Int32Array(H).fill(-1);
  let nCols = 0, nRows = 0;
  for (let x = 0; x < W; x++) {
    if (colHits[x] < (PY1 - PY0) * 0.4) continue;
    nCols++;
    for (let d = -5; d <= 5; d++) if (x + d >= 0 && x + d < W) colCenter[x + d] = x;
  }
  for (let y = 0; y < H; y++) {
    if (rowHits[y] < (PX1 - PX0) * 0.4) continue;
    nRows++;
    for (let d = -5; d <= 5; d++) if (y + d >= 0 && y + d < H) rowCenter[y + d] = y;
  }
  console.log(`  grille : ${nCols} colonnes + ${nRows} lignes détectées sur l'océan`);

  // Dans les bandes : test BILATÉRAL. Les deux références à ±8 px du CENTRE
  // du trait (hors trait et hors anticrénelage) doivent être d'accord entre
  // elles (≤30 par canal — le fond traverse la bande), et le pixel doit être
  // assombri par rapport à leur moyenne : somme des écarts 20..150, aucun
  // canal plus clair de >12. La grille assombrit de ~34 sur l'océan et ~94
  // sur la terre ; un texte ou une rue sombre qui croise la bande dévie de
  // bien plus (>240) et est épargné, une lisière de forêt aussi (~162).
  // Le rouge terne (grille sur fond clair) et l'océan assombri restent des
  // détections directes, sans référence.
  const isGridPx = new Uint8Array(W * H);
  let gridTotal = 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const cc = colCenter[x], rc = rowCenter[y];
      if (cc < 0 && rc < 0) continue;
      const o = (y * W + x) * 3;
      const pr = rawRgb[o], pg = rawRgb[o + 1], pb = rawRgb[o + 2];
      const lum = (pr + pg + pb) / 3;
      let hit = (pr > 150 && pr > pg + 30 && pb < 130 && lum < 160) || isDarkened(pr, pg, pb);
      if (!hit) {
        const aO = cc >= 0 ? (y * W + Math.max(0, cc - 8)) * 3 : (Math.max(0, rc - 8) * W + x) * 3;
        const bO = cc >= 0 ? (y * W + Math.min(W - 1, cc + 8)) * 3 : (Math.min(H - 1, rc + 8) * W + x) * 3;
        if (Math.abs(rawRgb[aO] - rawRgb[bO]) <= 30
          && Math.abs(rawRgb[aO + 1] - rawRgb[bO + 1]) <= 30
          && Math.abs(rawRgb[aO + 2] - rawRgb[bO + 2]) <= 30) {
          const dr = ((rawRgb[aO] + rawRgb[bO]) >> 1) - pr;
          const dg = ((rawRgb[aO + 1] + rawRgb[bO + 1]) >> 1) - pg;
          const db = ((rawRgb[aO + 2] + rawRgb[bO + 2]) >> 1) - pb;
          const dsum = dr + dg + db;
          hit = dr >= -12 && dg >= -12 && db >= -12 && dsum >= 20 && dsum <= 150;
        }
      }
      if (hit) {
        isGridPx[y * W + x] = 1;
        gridTotal++;
      }
    }
  }
  let gridSuppressed = 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      if (!isGridPx[i]) continue;
      let bestDist = 20, bestI = -1;
      for (const [dy, dx] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
        for (let d = 1; d <= 15; d++) {
          const nx = x + dx * d, ny = y + dy * d;
          if (nx < 0 || nx >= W || ny < 0 || ny >= H) break;
          if (!isGridPx[ny * W + nx]) {
            if (d < bestDist) { bestDist = d; bestI = ny * W + nx; }
            break;
          }
        }
      }
      if (bestI >= 0) {
        const o = i * 3, so = bestI * 3;
        rawRgb[o] = rawRgb[so]; rawRgb[o + 1] = rawRgb[so + 1]; rawRgb[o + 2] = rawRgb[so + 2];
        gridSuppressed++;
      }
    }
  }
  console.log(`  grille : ${gridTotal} détectés, ${gridSuppressed} → voisin`);

  const styled = restyle(rawRgb, info.width, info.height);
  console.log(`  restylage Neon Compass — ${styled.stats}  (${styled.colors} couleurs source, ${styled.labelUnified} px de libellés unifiés, ${styled.gridErased} axes fins, ${styled.oceanCleaned} isolés océan)`);

  // Aplatir l'océan profond à NIGHT_SKY exact. Le restylage quantifie
  // désormais le dégradé eau en 11 paliers, donc seuls les pixels les plus
  // sombres (proches de NIGHT_SKY) sont unifiés — le gradient côtier est
  // préservé.
  const NS = [0x0A, 0x08, 0x1A];
  let flattened = 0;
  for (let i = 0; i < info.width * info.height; i++) {
    if (!styled.ocean[i]) continue;
    const o = i * 3;
    const dr = styled.data[o] - NS[0], dg = styled.data[o + 1] - NS[1], db = styled.data[o + 2] - NS[2];
    if (dr * dr + dg * dg + db * db > 50) continue;
    styled.data[o] = NS[0]; styled.data[o + 1] = NS[1]; styled.data[o + 2] = NS[2];
    flattened++;
  }
  console.log(`  océan aplati : ${flattened} pixels → NIGHT_SKY exact (gradient préservé)`);

  // Recadrer sur l'île. Le scan exclut les zones d'effacement (panneau, labels)
  // pour éviter les faux bords créés par la dilatation du trait de côte.
  let bMinX = W, bMaxX = 0, bMinY = H, bMaxY = 0;
  const sL = 3100, sT = 450, sR = 500, sB = 450;
  for (let y = sT; y < H - sB; y++) {
    for (let x = sL; x < W - sR; x++) {
      if (!styled.ocean[y * W + x]) {
        if (x < bMinX) bMinX = x;
        if (x > bMaxX) bMaxX = x;
        if (y < bMinY) bMinY = y;
        if (y > bMaxY) bMaxY = y;
      }
    }
  }
  const margin = 80;
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
  image = cleanBuf;
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
  image = await encode(rawRgb, 'island-vi.png');
  console.log('  (--restyle non passé, island-vi.png = classique)');
}

writeFileSync(
  join(outDir, 'manifest-vi.json'),
  JSON.stringify({
    size,
    source: `gtavi:${MAP_AUTHOR}:${MAP_VERSION}:${style}:z${zoom}`,
    sourceSha256: createHash('sha256').update(image).digest('hex').slice(0, 16),
    pixels,
  }, null, 2) + '\n'
);

console.log(`  ${present.length}/${coords.length} tuiles présentes`);
