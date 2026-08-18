#!/usr/bin/env node
// Pavage haute définition de la carte communautaire de Leonida (YANIS v14).
//
// Produit, pour la restylée (island-vi) et la classic (island-vi-classic) :
//   - un SOCLE de 4 096 px, image unique, dessinée en permanence ;
//   - deux niveaux de tuiles de 512 px (9 216 / 18 432 px), tuiles uniformes
//     omises au profit d'une couleur dans le manifeste ;
//   - un manifeste décrivant les niveaux et les tuiles uniformes omises.
//
// Le brut z6 (79 tuiles, 20 224 px) est complété à 20 480 px en océan, traité
// par quatre quadrants à halo (gtavi-transform.mjs), puis recadré sur l'île —
// le double exact du cadrage que `gtavi-map.mjs` dérive de la bbox avec la
// plus grande marge symétrique que la source autorise. Ce cadrage a une
// valeur, pas une garantie de stabilité : il a changé une fois (tâche 10,
// élargissement des bordures d'océan) et toute position de POI normalisée
// avant ce commit ne désigne plus le même point — elle a dû être remappée
// (voir poi_sample_lighthouse).
//
//   node tools/basemap/gtavi-tiles.mjs [--style normal]
//
// Les deux étapes coûteuses — le téléchargement et l'assemblage — sont
// reprenables : elles sautent ce qui est déjà sur disque. C'est nécessaire et
// pas confortable : `fetch` tire 6 241 tuiles, et une coupure réseau au bout de
// 6 000 ne doit pas tout perdre. Le découpage, lui, repart de zéro — il ne
// coûte que du calcul local.

import { mkdirSync, writeFileSync, existsSync, statSync, openSync, readSync, writeSync, closeSync, unlinkSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { eraseAndDash, gridProbe, gridCenters, gridAndStyle, legendMask } from './gtavi-transform.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const CACHE = join(HERE, '.cache');
const TILES_DIR = join(ROOT, 'NeonCompass', 'Resources', 'MapTiles');
const ART_DIR = join(ROOT, 'NeonCompass', 'Resources', 'MapArt');

const TILE_BASE = 'https://map.stateofleonida.net/tiles';
const MAP_AUTHOR = 'YANIS';
const MAP_VERSION = 'v14';
const ZOOM = 6;
const SRC_TILE = 256;

export const SOURCE = { tile: SRC_TILE, grid: 79, side: 79 * SRC_TILE };

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}
const style = arg('style', 'normal');

export const stitchedPath = (s) => join(CACHE, `stitched-${s}.raw`);

const tileURL = (x, y) => `${TILE_BASE}/${MAP_AUTHOR}/${MAP_VERSION}/${style}/${ZOOM}/${x}/${y}.png`;

/// Le grid YANIS ne vaut pas 2^z — on le sonde, comme gtavi-map.mjs le fait
/// déjà à z5. Un écart avec SOURCE.grid arrête tout : les côtés de niveaux, le
/// nombre de tuiles et le manifeste en découlent tous.
async function probeGrid() {
  const base = `${TILE_BASE}/${MAP_AUTHOR}/${MAP_VERSION}/${style}/${ZOOM}`;
  const mid = Math.floor(2 ** ZOOM / 2);
  async function maxCoord(axis) {
    let hi = 2 ** ZOOM - 1;
    for (let c = hi + 1; c < hi + 24; c++) {
      const url = axis === 'x' ? `${base}/${c}/${mid}.png` : `${base}/${mid}/${c}.png`;
      try { const r = await fetch(url, { method: 'HEAD' }); if (!r.ok) break; hi = c; } catch { break; }
    }
    return hi + 1;
  }
  const [gx, gy] = await Promise.all([maxCoord('x'), maxCoord('y')]);
  return { gx, gy };
}

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
  let next = 0, done = 0;
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

/// Une tuile absente n'est PAS une erreur : le serveur ne sert pas les carrés
/// d'océan pur en bordure de grille. Elle est marquée manquante et le collage
/// y laissera la couleur d'océan, exactement comme gtavi-map.mjs à z5.
async function fetchAll() {
  const dir = join(CACHE, `z${ZOOM}-${style}`);
  mkdirSync(dir, { recursive: true });
  const jobs = [];
  for (let y = 0; y < SOURCE.grid; y++) {
    for (let x = 0; x < SOURCE.grid; x++) {
      jobs.push(async () => {
        const path = join(dir, `${x}_${y}.png`);
        if (existsSync(path) && statSync(path).size > 0) return true;
        try {
          writeFileSync(path, await fetchRetry(tileURL(x, y)));
          return true;
        } catch {
          writeFileSync(path, Buffer.alloc(0));   // marqueur d'absence, reprenable
          return false;
        }
      });
    }
  }
  const ok = await pool(jobs, 12, (d, t) => {
    if (d % 100 === 0 || d === t) process.stdout.write(`\r  ${d}/${t} tuiles`);
  });
  console.log(`\n  ${ok.filter(Boolean).length}/${jobs.length} tuiles présentes`);
  return dir;
}

/// Couleur d'océan, échantillonnée au centre de la tuile (0,0) — toujours de
/// l'eau. Sert de fond partout où une tuile manque, comme à z5.
async function oceanColor(dir) {
  const corner = join(dir, '0_0.png');
  if (!existsSync(corner) || statSync(corner).size === 0) throw new Error('tuile 0_0 absente : impossible d’échantillonner l’océan');
  const px = await sharp(corner).extract({ left: 100, top: 100, width: 1, height: 1 }).raw().toBuffer();
  return { r: px[0], g: px[1], b: px[2] };
}

/// Assemble en RGB brut sur disque. Aucun PNG intermédiaire : encoder puis
/// redécoder 1,2 Go ne servirait qu'à passer deux fois par zlib.
async function stitch(dir) {
  const out = stitchedPath(style);
  const expected = SOURCE.side * SOURCE.side * 3;
  if (existsSync(out) && statSync(out).size === expected) {
    console.log(`  ${out} déjà assemblé (${(expected / 2 ** 30).toFixed(2)} Gio)`);
    return out;
  }
  const ocean = await oceanColor(dir);
  const fd = openSync(out, 'w');
  for (let ty = 0; ty < SOURCE.grid; ty++) {
    const composite = [];
    for (let tx = 0; tx < SOURCE.grid; tx++) {
      const p = join(dir, `${tx}_${ty}.png`);
      if (existsSync(p) && statSync(p).size > 0) composite.push({ input: p, left: tx * SRC_TILE, top: 0 });
    }
    const strip = await sharp({
      create: { width: SOURCE.side, height: SRC_TILE, channels: 3, background: ocean },
    }).composite(composite).flatten({ background: ocean }).removeAlpha().raw().toBuffer();
    writeSync(fd, strip);
    process.stdout.write(`\r  bande ${ty + 1}/${SOURCE.grid}`);
  }
  closeSync(fd);
  console.log(`\n  ${out}  ${(statSync(out).size / 2 ** 30).toFixed(2)} Gio`);
  return out;
}

const { gx, gy } = await probeGrid();
if (gx !== SOURCE.grid || gy !== SOURCE.grid) {
  throw new Error(`grille inattendue : sondée ${gx}×${gy}, SOURCE.grid=${SOURCE.grid} — arrêt avant tout téléchargement`);
}

const dir = await fetchAll();
await stitch(dir);
const ocean = await oceanColor(dir);

// ---------------------------------------------------------------------------
// Tâche 3 : traiter le z6 par quadrants, en tirer la pyramide, le socle et le
// manifeste. Le brut assemblé ci-dessus fait 20224 px (79 tuiles) ; il est
// complété à 20480 (Step 1) pour que toute la géométrie du z5 — exprimée en
// unités z5 par gtavi-transform.mjs — reste valable au facteur 2 exact.

const REF_SIDE = 10240;                 // le z5
const SIDE = 20480;                     // 2 × REF_SIDE
const SCALE = SIDE / REF_SIDE;          // vaut 2, et le module le recalcule seul

/// Complète le brut assemblé de SOURCE.side à SIDE, en océan. Reprenable :
/// si le fichier complété existe déjà à la bonne taille, ne rien faire.
function padded(s, oc) {
  const src = stitchedPath(s);
  const dst = join(CACHE, `padded-${s}.raw`);
  const want = SIDE * SIDE * 3;
  if (existsSync(dst) && statSync(dst).size === want) return dst;

  const row = Buffer.alloc(SIDE * 3);
  for (let x = 0; x < SIDE; x++) { row[x * 3] = oc.r; row[x * 3 + 1] = oc.g; row[x * 3 + 2] = oc.b; }
  const fin = openSync(src, 'r'), fout = openSync(dst, 'w');
  const line = Buffer.allocUnsafe(SOURCE.side * 3);
  for (let y = 0; y < SIDE; y++) {
    const out = Buffer.from(row);
    if (y < SOURCE.side) {
      readSync(fin, line, 0, line.length, y * SOURCE.side * 3);
      line.copy(out, 0);
    }
    writeSync(fout, out, 0, out.length);
  }
  closeSync(fin); closeSync(fout);
  return dst;
}

// Step 3 : les deux passes de quadrants. Quatre cœurs de 10240 px, halo de
// 1024 px, fenêtres de 11264 px.
const HALO = 1024;
const CORE = SIDE / 2;
const CORES = [
  { x: 0, y: 0, w: CORE, h: CORE }, { x: CORE, y: 0, w: CORE, h: CORE },
  { x: 0, y: CORE, w: CORE, h: CORE }, { x: CORE, y: CORE, w: CORE, h: CORE },
];
const FULL = { w: SIDE, h: SIDE };

const windowOf = (core) => {
  const x = Math.max(0, core.x - HALO), y = Math.max(0, core.y - HALO);
  return { x, y, w: Math.min(SIDE, core.x + core.w + HALO) - x,
                 h: Math.min(SIDE, core.y + core.h + HALO) - y };
};

/// Lit une fenêtre d'un brut sur disque, ligne par ligne.
function readWindow(path, win) {
  const fd = openSync(path, 'r');
  const buf = Buffer.allocUnsafe(win.w * win.h * 3);
  for (let y = 0; y < win.h; y++) {
    readSync(fd, buf, y * win.w * 3, win.w * 3, ((win.y + y) * SIDE + win.x) * 3);
  }
  closeSync(fd);
  return buf;
}

/// Écrit un cœur dans un brut sur disque, ligne par ligne.
function writeCore(fd, core, data) {
  for (let y = 0; y < core.h; y++) {
    writeSync(fd, data, y * core.w * 3, core.w * 3, ((core.y + y) * SIDE + core.x) * 3);
  }
}

async function transformAll(s, oc) {
  const src = padded(s, oc);
  const mid = join(CACHE, `mid-${s}.raw`);
  const out = join(CACHE, `styled-${s}.raw`);

  // Passe A — effacement, tirets, contribution au sondage.
  // `core` est passé à eraseAndDash pour BORNER SES COMPTEURS, pas son
  // traitement : celui-ci porte sur toute la fenêtre, halo compris. Seul
  // `dashCompsInWindow` reste à portée de fenêtre — son nom le dit, et il ne
  // faut donc pas le sommer sur les quatre quadrants.
  const colHits = new Uint32Array(SIDE), rowHits = new Uint32Array(SIDE);
  const fmid = openSync(mid, 'w+');
  for (const core of CORES) {
    const win = windowOf(core);
    const buf = readWindow(src, win);
    const a = eraseAndDash(buf, win, FULL, oc, core);
    const p = gridProbe(buf, win, FULL, core);
    for (let i = 0; i < SIDE; i++) { colHits[i] += p.colHits[i]; rowHits[i] += p.rowHits[i]; }
    // Prélever le cœur de la fenêtre avant de l'écrire.
    const cw = Buffer.allocUnsafe(core.w * core.h * 3);
    for (let y = 0; y < core.h; y++) {
      buf.copy(cw, y * core.w * 3,
               ((core.y - win.y + y) * win.w + (core.x - win.x)) * 3,
               ((core.y - win.y + y) * win.w + (core.x - win.x) + core.w) * 3);
    }
    writeCore(fmid, core, cw);
    console.log(`  quadrant ${core.x / CORE},${core.y / CORE} A : ${a.erased} effacés, ${a.dashCompsInWindow} tirets (fenêtre), ${a.dashSuppressed} px → voisin`);
  }
  closeSync(fmid);

  const centers = gridCenters(colHits, rowHits, FULL);
  console.log(`  grille : ${centers.nCols} colonnes + ${centers.nRows} lignes détectées sur l'océan`);

  // Passe B — grille, restylage, aplatissement. Et la boîte englobante, pour
  // contrôle : elle n'est pas utilisée pour recadrer, seulement pour vérifier.
  const fout = openSync(out, 'w+');
  let bb = null;
  for (const core of CORES) {
    const win = windowOf(core);
    const r = gridAndStyle(readWindow(mid, win), win, FULL, core, centers);
    for (let y = 0; y < core.h; y++) {
      let n = 0;
      for (let x = 0; x < core.w; x++) if (!r.ocean[y * core.w + x]) n++;
      rowInk[core.y + y] += n;
    }
    writeCore(fout, core, r.data);
    if (r.bbox) {
      bb = bb ? { minX: Math.min(bb.minX, r.bbox.minX), maxX: Math.max(bb.maxX, r.bbox.maxX),
                  minY: Math.min(bb.minY, r.bbox.minY), maxY: Math.max(bb.maxY, r.bbox.maxY) } : r.bbox;
    }
    console.log(`  quadrant ${core.x / CORE},${core.y / CORE} B : ${r.gridSuppressed} px de grille, ${r.flattened} aplatis — ${r.stats}`);
  }
  closeSync(fout);
  // `mid` n'est plus utile à personne : Passe A l'a écrit, Passe B vient de le
  // lire pour la dernière fois.
  unlinkSync(mid);
  return { path: out, bbox: bb };
}

// Step 4 : le recadrage, doublé et non recalculé. Ce n'est plus le cadrage
// « du z5 livré » : c'est celui que gtavi-map.mjs dérive de la bbox avec la
// marge maximale symétrique (tâche 10, Step 1) — left 706, top 706, 9534×9534
// — et les épingles posées désignent des points de ce cadre.
const CROP = { left: 706 * SCALE, top: 706 * SCALE, side: 9534 * SCALE };

/// Le nombre de pixels non-océan par LIGNE GLOBALE, cumulé sur les quatre
/// quadrants — une ligne traverse deux quadrants, il faut donc les sommer.
/// Alimenté dans la boucle de la passe B de transformAll, juste après
/// gridAndStyle.
const rowInk = new Uint32Array(FULL.h);

/// La première ligne portant assez d'encre pour être une côte, et non un
/// éclat de classification isolé.
///
/// POURQUOI PAS `bbox.minY` : le `min()` de la boîte englobante retient le
/// PREMIER pixel non-océan, quel qu'il soit. Mesuré sur le z5 livré, ligne
/// par ligne : `minY = 1174` avec **n = 1**, un pixel unique, quand la côte
/// ne commence qu'à **1249** (n = 121) et que la première terre de la source
/// brute est à 1246. La borne nord de la boîte englobante n'a donc jamais
/// mesuré une côte — elle mesurait du bruit, aux deux échelles à la fois.
/// Le contrôle comparait du bruit à du bruit.
///
/// Le seuil suit l'échelle et non son carré : une même bande géographique
/// occupe `scale` fois plus de pixels par ligne. 64 à z5, 128 à z6.
function coastTop(ink, scale) {
  const seuil = 64 * scale;
  for (let y = 0; y < ink.length; y++) if (ink[y] >= seuil) return y;
  return -1;
}

/// Le cadre doit contenir l'île, et de peu. Le contrôle est là pour attraper
/// une constante d'échelle mal transposée en tâche 2 : si le classificateur
/// dérape, la boîte englobante déborde et on l'apprend ici plutôt qu'à l'œil.
///
/// TROIS bords se comparent au z5 doublé, et y tombent à 2 px près. Le
/// QUATRIÈME, le nord, ne le peut pas — et ce n'est pas un défaut de mesure,
/// c'est une propriété que le pipeline n'a pas. Mesuré aux quatre coins :
///
///                 source brute   après restylage
///   z5              1283            1249   (le restylage AVANCE de 34 px)
///   z6 (en z5)      1275            1333   (il RECULE de 58 px)
///
/// La source double exactement — 1283 × 2 = 2566 prédit contre ~2550 mesuré.
/// C'est le restylage qui diverge, d'environ 90 px z5, et dans des sens
/// OPPOSÉS aux deux échelles : la brume côtière ténue au nord de l'île tombe
/// d'un côté ou de l'autre du classificateur selon la finesse. Le rendu z6
/// est correct — côte nette, dégradé d'océan propre, aucune pointe rabotée.
///
/// Le nord assure donc ce qu'il peut assurer, et ça reste falsifiable : la
/// côte est au SUD du cadre (rien de réel n'est perdu au recadrage) et pas
/// absurdement loin au sud (le classificateur n'a pas mangé la pointe).
function checkCrop(bbox, rowInk) {
  const ref = { minX: 3440 * SCALE, maxX: 9645 * SCALE, maxY: 9771 * SCALE };
  const tol = 64 * SCALE;
  for (const k of ['minX', 'maxX', 'maxY']) {
    if (Math.abs(bbox[k] - ref[k]) > tol) {
      throw new Error(`boîte englobante ${k}=${bbox[k]}, attendu ${ref[k]} ±${tol} — `
        + `une constante d'échelle est fausse, voir la table de la tâche 2`);
    }
  }
  const cote = coastTop(rowInk, SCALE);
  const planchier = CROP.top, plafond = 1249 * SCALE + 256 * SCALE;
  if (!(cote > planchier && cote < plafond)) {
    throw new Error(`côte nord à y=${cote}, attendue dans ]${planchier}, ${plafond}[ — `
      + `sous le cadre elle serait perdue au recadrage, au-delà le classificateur `
      + `a mangé la pointe de l'île`);
  }
}

// Step 6 : découper la pyramide. Le recadrage fait 19 068 px ; le niveau le
// plus fin est 18 432 (512×36) — c'est le PLUS GRAND qui satisfasse les deux
// contraintes à la fois : rester sous 19 068, donc réduire et jamais
// interpoler des pixels qui n'existent pas ; et être un multiple PAIR de 512,
// pour que sa moitié tombe elle aussi sur la grille. 512×37 = 18 944 passe la
// première et échoue la seconde (9 472 n'est pas un multiple de 512).
const TILE = 512;
const LEVELS = [18432, 9216];   // du plus fin au plus grossier
const BASE = 4096;              // le socle, image unique — le palier suivant de
                                 // la même chaîne, qu'il est inutile de paver
const UNIFORM_TOL = 2;          // écart max sur les trois canaux
const NIGHT_SKY = { r: 0x0A, g: 0x08, b: 0x1A };

/// Lit le recadrage depuis le brut restylé et le rend à `side` px.
async function levelBuffer(rawPath, side, background) {
  const crop = Buffer.allocUnsafe(CROP.side * CROP.side * 3);
  const fd = openSync(rawPath, 'r');
  for (let y = 0; y < CROP.side; y++) {
    readSync(fd, crop, y * CROP.side * 3, CROP.side * 3,
             ((CROP.top + y) * SIDE + CROP.left) * 3);
  }
  closeSync(fd);
  // Rendu en BRUT et non en PNG : le découpage qui suit prélève ses tuiles par
  // recopie mémoire. Rendre un PNG obligerait sharp à le redécoder à chaque
  // extraction — 1 296 décodages d'une image de 1 019 Mo au niveau le plus fin.
  // `limitInputPixels: false` : le garde-fou anti-decompression-bomb de sharp
  // (≈268 M px) est fait pour des fichiers d'origine EXTERNE et non fiable ;
  // CROP.side=19068 (≈364 M px) est une constante interne connue, pas une
  // entrée arbitraire.
  return sharp(crop, {
    raw: { width: CROP.side, height: CROP.side, channels: 3 },
    limitInputPixels: false,
  })
    .resize(side, side, { kernel: 'lanczos3' })
    .sharpen({ sigma: 1, m1: 0.6, m2: 2 })
    .flatten({ background })
    .removeAlpha()          // `flatten` promeut en RGBA ; le brut doit rester à 3 canaux
    .raw()
    .toBuffer();
}

/// Découpe un niveau en tuiles. Une tuile dont les trois canaux varient de
/// moins de UNIFORM_TOL n'est pas écrite : sa couleur va au manifeste, et
/// l'app peindra un calque uni. 27 % des tuiles du niveau 9 216 dans la carte
/// livrée — le gain est réel et il évite autant de décodages.
async function cutLevel(name, side, raw) {
  const dir2 = join(TILES_DIR, name, String(side));
  // Effacé puis recréé, jamais fusionné à ce qui existait déjà : une exécution
  // antérieure peut avoir écrit un PNG à un x_y que CETTE exécution juge
  // désormais uniforme (contenu source changé, recadrage changé...). Sans ce
  // ménage, le fichier périmé survit à côté d'une entrée `uniform` qui dit le
  // contraire — le disque et le manifeste se contredisent, sans que rien ne
  // le remarque.
  rmSync(dir2, { recursive: true, force: true });
  mkdirSync(dir2, { recursive: true });
  const n = side / TILE;
  const uniform = {};
  let written = 0;
  const tile = Buffer.allocUnsafe(TILE * TILE * 3);

  for (let ty = 0; ty < n; ty++) {
    for (let tx = 0; tx < n; tx++) {
      // Prélèvement par recopie de lignes. Le brut est en mémoire, donc c'est
      // un memcpy de 1,5 Ko par ligne — rien à décoder.
      for (let y = 0; y < TILE; y++) {
        const from = ((ty * TILE + y) * side + tx * TILE) * 3;
        raw.copy(tile, y * TILE * 3, from, from + TILE * 3);
      }

      // Uniformité jugée sur le BRUT, avant tout encodage : c'est exact, et la
      // quantification en palette pourrait sinon rendre uniforme une tuile qui
      // ne l'est pas — ou l'inverse.
      let rMin = 255, rMax = 0, gMin = 255, gMax = 0, bMin = 255, bMax = 0;
      for (let i = 0; i < tile.length; i += 3) {
        const r = tile[i], g = tile[i + 1], b = tile[i + 2];
        if (r < rMin) rMin = r; if (r > rMax) rMax = r;
        if (g < gMin) gMin = g; if (g > gMax) gMax = g;
        if (b < bMin) bMin = b; if (b > bMax) bMax = b;
      }
      if (rMax - rMin <= UNIFORM_TOL && gMax - gMin <= UNIFORM_TOL && bMax - bMin <= UNIFORM_TOL) {
        const hex = [(rMin + rMax) >> 1, (gMin + gMax) >> 1, (bMin + bMax) >> 1]
          .map((c) => c.toString(16).padStart(2, '0').toUpperCase()).join('');
        uniform[`${tx}_${ty}`] = hex;
        continue;
      }

      writeFileSync(join(dir2, `${tx}_${ty}.png`), await sharp(tile, {
        raw: { width: TILE, height: TILE, channels: 3 },
      }).png({ palette: true, colors: 256, effort: 9 }).toBuffer());
      written++;
    }
  }
  return { side, count: n, written, uniform };
}

// Step 7 : le socle et la classic. La classic ne passe par aucun quadrant :
// c'est la source complétée plus l'effacement de légende, et rien d'autre —
// exactement ce que `erasedOut` capture dans gtavi-map.mjs. `legendMask` est
// désormais exportée par gtavi-transform.mjs (une seule définition, partagée
// avec eraseAndDash) : on ne récrit pas le prédicat ici.
/// Produit le brut de la classic en une passe de lecture-écriture ligne par
/// ligne sur le brut complété — pas de quadrants, pas de grille ni de tirets
/// retirés, seulement la légende. Reprenable comme `padded`.
function classicRaw(s, oc) {
  const src = padded(s, oc);
  const dst = join(CACHE, `classic-${s}.raw`);
  const want = SIDE * SIDE * 3;
  if (existsSync(dst) && statSync(dst).size === want) return dst;

  const inLegend = legendMask(FULL);
  const fin = openSync(src, 'r'), fout = openSync(dst, 'w');
  const line = Buffer.allocUnsafe(SIDE * 3);
  for (let y = 0; y < SIDE; y++) {
    readSync(fin, line, 0, line.length, y * SIDE * 3);
    for (let x = 0; x < SIDE; x++) {
      if (!inLegend(x, y)) continue;
      const o = x * 3;
      line[o] = oc.r; line[o + 1] = oc.g; line[o + 2] = oc.b;
    }
    writeSync(fout, line, 0, line.length);
  }
  closeSync(fin); closeSync(fout);
  return dst;
}

/// Pave les deux niveaux et tire le socle d'une carte depuis son brut. Les
/// deux passent par le MÊME recadrage (CROP) — une seule provenance, donc
/// aucune dérive de sous-pixel entre le socle et les tuiles posées dessus.
async function buildMap(name, rawPath, background) {
  const levels = [];
  for (const side of LEVELS) {
    const raw = await levelBuffer(rawPath, side, background);
    const level = await cutLevel(name, side, raw);
    console.log(`  ${name} @ ${side}px : ${level.written} tuiles écrites, ${Object.keys(level.uniform).length} uniformes sur ${level.count * level.count}`);
    levels.push(level);
  }
  const base = await levelBuffer(rawPath, BASE, background);
  writeFileSync(join(ART_DIR, `${name}.png`), await sharp(base, {
    raw: { width: BASE, height: BASE, channels: 3 },
  }).png({ palette: true, colors: 256, effort: 9 }).toBuffer());
  console.log(`  ${name}.png (socle ${BASE}px) écrit`);
  // Du plus grossier au plus fin — Step 8 : la tâche 5 parcourt la liste dans
  // cet ordre et s'arrête au premier niveau assez fin.
  return levels.sort((a, b) => a.side - b.side);
}

// Step 8 : écrire les manifestes.
function writeManifest(name, levels) {
  mkdirSync(TILES_DIR, { recursive: true });
  const manifest = {
    tile: TILE,
    // Le côté du SOCLE, et il n'est pas décoratif : c'est sous cette taille
    // que l'app ne charge aucune tuile, le socle en montrant déjà autant que
    // l'écran peut afficher. Le lire ici plutôt que de le réécrire en Swift
    // évite la seule dérive qui ne se verrait pas — un socle changé d'un côté
    // seulement engagerait un niveau de tuiles trop tôt, ou pas assez tôt,
    // sans que rien n'échoue.
    base: BASE,
    source: `gtavi:${MAP_AUTHOR}:${MAP_VERSION}:${style}:z${ZOOM}`,
    levels: levels.map(({ side, count, uniform }) => ({ side, count, uniform })),
  };
  writeFileSync(join(TILES_DIR, `${name}.json`), JSON.stringify(manifest, null, 2) + '\n');
  console.log(`  ${name}.json écrit — ${manifest.levels.length} niveaux`);
}

// --- Orchestration ---
mkdirSync(ART_DIR, { recursive: true });
mkdirSync(TILES_DIR, { recursive: true });

console.log(`\n=== pyramide z6 (${style}) ===`);
const paddedPath = padded(style, ocean);
console.log(`  brut complété : ${paddedPath}`);

console.log('\n--- restylée (island-vi) ---');
const styled = await transformAll(style, ocean);
checkCrop(styled.bbox, rowInk);
console.log('  boîte englobante dans la tolérance de checkCrop');
const viLevels = await buildMap('island-vi', styled.path, NIGHT_SKY);
// `styled` n'a plus de consommateur : les deux niveaux et le socle sont tirés.
unlinkSync(styled.path);
writeManifest('island-vi', viLevels);

console.log('\n--- classic (island-vi-classic) ---');
const classicPath = classicRaw(style, ocean);
// `padded` n'a plus de consommateur : la restylée l'a lu (via transformAll),
// la classic aussi — à l'instant.
unlinkSync(paddedPath);
const classicLevels = await buildMap('island-vi-classic', classicPath, ocean);
unlinkSync(classicPath);
writeManifest('island-vi-classic', classicLevels);

console.log('\n  terminé.');
