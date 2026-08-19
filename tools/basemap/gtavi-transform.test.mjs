// Découper une image en quadrants avec halo et ne garder que les cœurs doit
// rendre la même image que la traiter d'un bloc, ET les mêmes compteurs une
// fois sommés. Ce n'est pas exact par construction pour la passe de tirets — la
// confirmation par colinéarité se propage de proche en proche sur toute la
// longueur d'une limite de comté, sans borne — donc on MESURE l'écart au lieu
// de le postuler.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { eraseAndDash, gridProbe, gridCenters, gridAndStyle, REF } from './gtavi-transform.mjs';
import { restyle } from './gtavi-restyle.mjs';

const W = 2048, H = 2048;
const FULL = { w: W, h: H };
const WHOLE = { x: 0, y: 0, w: W, h: H };
const OCEAN = { r: 44, g: 103, b: 164 };

// Tolérance de la comparaison quadrants/bloc. Sur cette image d'épreuve elle
// n'est pas consommée — l'égalité est exacte, et c'est ce que le test exige.
// Elle reste écrite ici parce qu'elle vaut pour l'IMAGE RÉELLE, où une limite
// de comté court sur plus que le halo et où la propagation peut diverger : le
// test « sans halo » s'y compare pour rester le pendant du test avec halo.
const ALLOWANCE = 0.0002;

/// Image d'épreuve. Elle contient ce qui casse un découpage naïf : un panneau
/// de légende à gauche, une LIGNE DE TIRETS traversant tout le cadre (la seule
/// figure globalement couplée), des lignes de grille verticale ET horizontale,
/// un fragment de colonne conçu pour ne passer le seuil de détection QUE s'il
/// est compté deux fois, et des libellés à cheval sur la coupure horizontale.
///
/// Les figures sont dessinées à l'échelle de L'ÉPREUVE, pas à celle du z5.
/// `scale` vaut ici 2048/10240 = 0,2 : un tiret doit donc faire 2×8 px et non
/// 6×40, et son aire se compare à 1500×0,2² = 60. Dessinées à la taille du z5,
/// toutes les figures sont rejetées par les seuils, le découpage n'a plus rien
/// à casser et les tests passent sans rien prouver.
function fixture() {
  const d = Buffer.alloc(W * H * 3);
  const put = (x, y, r, g, b) => {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const o = (y * W + x) * 3; d[o] = r; d[o + 1] = g; d[o + 2] = b;
  };
  const DARK = [47, 95, 141];    // océan assombri par un trait de grille
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (x < 900) put(x, y, 44, 103, 164);            // océan pur, à l'ouest
    else put(x, y, 190, 180, 150);                    // terre
  }
  for (let y = 0; y < H; y++) for (let x = 0; x < 400; x++) put(x, y, 252, 252, 252); // panneau
  // Colonne de grille, sur toute la hauteur. x=700 est à 65 px du bord de halo
  // le plus proche (768), donc jamais dans un recouvrement : elle vaut 112
  // relevés quelle que soit la découpe.
  for (let y = 0; y < H; y++) for (let x = 700; x < 703; x++) put(x, y, ...DARK);
  // LIGNE de grille horizontale, à y=1300 : sans elle, nRows vaut 0 et toute la
  // branche « ligne » du test bilatéral de gridAndStyle est morte dans
  // l'épreuve — y compris la conversion de coordonnée ly(), qui est l'identité
  // au z5 puisque win.y y vaut 0. y=1300 tombe dans les quadrants du bas, dont
  // la fenêtre commence à 768 : ly() y est enfin autre chose que l'identité.
  // Sa part océan (à l'ouest) sert au SONDAGE, qui n'échantillonne que
  // x∈[601,680[ ; sa part TERRE sert à faire réellement FEU au test bilatéral.
  // Sur l'océan la ligne est détectée directement, par isDarkened, et la
  // branche s'exécute sans jamais changer d'avis — retirer ly() y resterait
  // sans effet. Sur la terre le pixel n'est pas détectable par sa seule
  // couleur : il faut lire les deux références à rc±8×échelle, et c'est là que
  // la conversion de coordonnée porte.
  for (let y = 1300; y < 1303; y++) {
    for (let x = 600; x < 900; x++) put(x, y, ...DARK);
    for (let x = 1400; x < 1900; x++) put(x, y, 175, 165, 135);   // terre assombrie
  }
  // FRAGMENT de colonne, à cheval sur le recouvrement des halos (x∈[768,1280[)
  // et haut de 30 lignes seulement dans la bande de sondage, qui en compte 112.
  // Le seuil est à 40 % soit 44,8 : compté une fois (30) il est rejeté, compté
  // deux fois (60) il devient une colonne et nCols passe de 3 à 6. C'est le
  // contrôle du contrat « gridProbe ne sonde QUE le cœur ».
  for (let y = 84; y < 114; y++) for (let x = 800; x < 803; x++) put(x, y, ...DARK);
  // De quoi rendre non nuls les compteurs que les figures précédentes laissent
  // à zéro — un `deepEqual` sur des zéros n'est le contrôle de rien.
  //   · un résidu d'axe fin (rouge TERNE, r−g = 86 < 115) posé en travers de la
  //     coupure verticale : c'est `gridErased`, donc la passe que F1 concerne ;
  for (let x = 1000; x < 1800; x++) put(x, 1500, 170, 84, 84);
  //   · quatre grains de terre isolés au large : c'est `oceanCleaned` ;
  for (const [x, y] of [[640, 1020], [650, 1030], [660, 300], [670, 1500]]) put(x, y, 190, 180, 150);
  //   · une nappe d'océan PROFOND (luminance 63, le palier 0 du dégradé) à
  //     cheval sur la coupure horizontale : c'est `flattened` ;
  for (let y = 900; y < 1150; y++) for (let x = 750; x < 890; x++) put(x, y, 10, 40, 140);
  //   · un libellé pâle de 20×20 — aire 400, sous le plafond de 480, donc
  //     réellement uniformisé — lui aussi à cheval sur la coupure : c'est
  //     `labelUnified`, le seul compteur qui porte sur une COMPOSANTE et doit
  //     donc se compter membre par membre pour se ramener à un cœur.
  for (let y = 1014; y < 1034; y++) for (let x = 1900; x < 1920; x++) put(x, y, 210, 215, 190);
  // Tirets roses de 8 px espacés de 6, sur toute la hauteur : la limite de
  // comté. Le segment y=1022..1029 est à cheval sur la coupure horizontale ;
  // coupé, sa moitié haute (2×2) n'est plus allongée et cesse d'être un tiret.
  for (let seg = 0; seg * 14 < H; seg++) {
    for (let y = seg * 14; y < seg * 14 + 8 && y < H; y++) {
      for (let x = 1200; x < 1202; x++) put(x, y, 238, 100, 100);
    }
  }
  // Libellés pâles de 22×40, centrés sur la coupure y = 1024. Entiers, ils
  // dépassent le plafond d'aire de l'uniformisation des libellés (880 > 480)
  // et gardent leur couleur ; coupés en deux ils passent (440) et sont
  // repeints en blanc-lavande. C'est précisément ce que le halo empêche.
  for (let k = 0; k < 8; k++) {
    for (let y = 1004; y < 1044; y++) {
      for (let x = 1300 + k * 40; x < 1322 + k * 40; x++) put(x, y, 210, 215, 190);
    }
  }
  return d;
}

const COUNTERS = ['erased', 'dashSuppressed', 'gridTotal', 'gridSuppressed',
                  'flattened', 'labelUnified', 'gridErased', 'oceanCleaned'];

/// Le traitement complet d'une découpe donnée. `cores` liste les cœurs ;
/// un seul cœur couvrant tout, c'est le traitement d'un bloc.
/// @returns {{img, centers, sums, bbox}} — `sums` additionne les compteurs de
///          pixels des cœurs, `bbox` unit leurs boîtes englobantes.
function run(cores, halo) {
  const src = fixture();
  const win = (core) => {
    const x = Math.max(0, core.x - halo), y = Math.max(0, core.y - halo);
    return {
      x, y,
      w: Math.min(W, core.x + core.w + halo) - x,
      h: Math.min(H, core.y + core.h + halo) - y,
    };
  };
  const cut = (buf, wn) => {
    const out = Buffer.allocUnsafe(wn.w * wn.h * 3);
    for (let y = 0; y < wn.h; y++) {
      buf.copy(out, y * wn.w * 3, ((wn.y + y) * W + wn.x) * 3, ((wn.y + y) * W + wn.x + wn.w) * 3);
    }
    return out;
  };
  const sums = Object.fromEntries(COUNTERS.map(k => [k, 0]));
  const add = (r) => { for (const k of COUNTERS) if (k in r) sums[k] += r[k]; };

  // Phase A sur chaque fenêtre ; on recolle les cœurs dans un intermédiaire.
  const mid = Buffer.alloc(W * H * 3);
  const colHits = new Uint32Array(W), rowHits = new Uint32Array(H);
  for (const core of cores) {
    const wn = win(core);
    const buf = cut(src, wn);
    add(eraseAndDash(buf, wn, FULL, OCEAN, core));
    const p = gridProbe(buf, wn, FULL, core);
    for (let i = 0; i < W; i++) colHits[i] += p.colHits[i];
    for (let i = 0; i < H; i++) rowHits[i] += p.rowHits[i];
    for (let y = 0; y < core.h; y++) {
      buf.copy(mid, ((core.y + y) * W + core.x) * 3,
               ((core.y - wn.y + y) * wn.w + (core.x - wn.x)) * 3,
               ((core.y - wn.y + y) * wn.w + (core.x - wn.x) + core.w) * 3);
    }
  }
  const centers = gridCenters(colHits, rowHits, FULL);

  // Phase B sur chaque fenêtre de l'intermédiaire.
  const img = Buffer.alloc(W * H * 3);
  let bbox = null;
  for (const core of cores) {
    const wn = win(core);
    const r = gridAndStyle(cut(mid, wn), wn, FULL, core, centers);
    add(r);
    if (r.bbox) {
      bbox = bbox === null ? { ...r.bbox } : {
        minX: Math.min(bbox.minX, r.bbox.minX), maxX: Math.max(bbox.maxX, r.bbox.maxX),
        minY: Math.min(bbox.minY, r.bbox.minY), maxY: Math.max(bbox.maxY, r.bbox.maxY),
      };
    }
    for (let y = 0; y < core.h; y++) {
      r.data.copy(img, ((core.y + y) * W + core.x) * 3, y * core.w * 3, (y + 1) * core.w * 3);
    }
  }
  return { img, centers, sums, bbox };
}

const QUADRANTS = [
  { x: 0, y: 0, w: 1024, h: 1024 }, { x: 1024, y: 0, w: 1024, h: 1024 },
  { x: 0, y: 1024, w: 1024, h: 1024 }, { x: 1024, y: 1024, w: 1024, h: 1024 },
];
const BOTTOM_RIGHT = { x: 1024, y: 1024, w: 1024, h: 1024 };

const compare = (a, b) => {
  let diff = 0, firstAt = -1;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) { diff++; if (firstAt < 0) firstAt = i; }
  }
  return { diff, ratio: diff / a.length, x: (firstAt / 3 | 0) % W, y: (firstAt / 3 / W) | 0 };
};

test('la référence d’échelle est le z5', () => {
  assert.equal(REF, 10240);
});

test('une géométrie de référence qui n’est pas un multiple de REF est refusée', () => {
  // Le brut assemblé du z6 fait 79×256 = 20224 : pris au mot il donnerait
  // scale = 1,975 et laisserait 75 px de panneau de légende debout.
  assert.throws(() => gridCenters(new Uint32Array(1), new Uint32Array(1), { w: 20224, h: 20224 }),
    /multiple exact de REF/);
  assert.throws(() => eraseAndDash(Buffer.alloc(3), { x: 0, y: 0, w: 1, h: 1 },
    { w: 20224, h: 20224 }, OCEAN, { x: 0, y: 0, w: 1, h: 1 }), /multiple exact de REF/);
});

test('les sondes de voisinage suivent l’échelle', () => {
  // Un résidu de grille fait 2 px de large au z5 et 4 au z6. Son effacement
  // repose sur une mesure d'ÉPAISSEUR par sondes à ±R. Un R figé à 2 rend le
  // test toujours faux sur un trait de 4 px : la passe cesse d'effacer quoi que
  // ce soit, sans erreur, sans journal et — sans ce contrôle — sans test rouge.
  // Le trait est en rouge terne (170,84,84) → ROAD, sur fond de terre.
  const w = 64, h = 64;
  const line = (thick) => {
    const d = Buffer.alloc(w * h * 3);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 3, on = x >= 30 && x < 30 + thick;
      d[o] = on ? 170 : 190; d[o + 1] = on ? 84 : 180; d[o + 2] = on ? 84 : 150;
    }
    return d;
  };
  assert.ok(restyle(line(2), w, h, 1).gridErased > 0, 'trait de 2 px à l’échelle 1');
  assert.ok(restyle(line(4), w, h, 2).gridErased > 0, 'trait de 4 px à l’échelle 2');
});

test('quatre quadrants avec halo rendent la même image qu’un bloc', () => {
  const whole = run([WHOLE], 0);
  const split = run(QUADRANTS, 256);
  const c = compare(whole.img, split.img);
  // Égalité EXACTE, et non « sous le plafond » : mesurée à 0 octet sur cette
  // image, un plafond y laisserait passer une régression de 12 000 octets.
  assert.equal(c.diff, 0,
    `${c.diff} octets diffèrent (${(c.ratio * 100).toFixed(4)} %), premier en x=${c.x}, y=${c.y}`);
});

test('un halo nul, lui, casse la couture — le contrôle sait échouer', () => {
  const whole = run([WHOLE], 0);
  const naive = run(QUADRANTS, 0);
  const c = compare(whole.img, naive.img);
  assert.ok(c.ratio > ALLOWANCE,
    `sans halo l’écart devrait dépasser la tolérance, il vaut ${(c.ratio * 100).toFixed(4)} %`);
});

test('le sondage de la grille ne compte que le cœur, jamais le halo', () => {
  const whole = run([WHOLE], 0);
  const split = run(QUADRANTS, 256);
  // Le fragment de colonne posé dans le recouvrement des halos ne franchit le
  // seuil que s'il est relevé deux fois : nCols passerait de 3 à 6.
  assert.deepEqual(
    { nCols: split.centers.nCols, nRows: split.centers.nRows },
    { nCols: 3, nRows: 3 },
    'le découpage a inventé ou perdu des traits de grille');
  assert.equal(split.centers.nCols, whole.centers.nCols);
  assert.equal(split.centers.nRows, whole.centers.nRows);
});

test('la boîte englobante est en coordonnées globales', () => {
  // Un seul cœur, celui du bas à droite : une boîte exprimée en coordonnées de
  // tampon y serait forcément < 1024, puisque le cœur fait 1024 de côté.
  const br = run([BOTTOM_RIGHT], 0);
  assert.ok(br.bbox && br.bbox.minX >= BOTTOM_RIGHT.x && br.bbox.minY >= BOTTOM_RIGHT.y,
    `boîte locale au lieu de globale : ${JSON.stringify(br.bbox)}`);
  // Et l'union des quatre cœurs vaut la boîte du bloc entier.
  assert.deepEqual(run(QUADRANTS, 256).bbox, run([WHOLE], 0).bbox);
});

test('les compteurs de pixels se somment sur les cœurs', () => {
  const whole = run([WHOLE], 0);
  const split = run(QUADRANTS, 256);
  // `erased` est celui dont la tâche 3 attend qu'il quadruple exactement d'un
  // niveau de zoom au suivant ; les autres suivent la même règle de portée.
  assert.deepEqual(split.sums, whole.sums,
    'un compteur porte sur la fenêtre au lieu du cœur — les halos comptent double');
  assert.ok(whole.sums.erased > 0, 'l’épreuve doit réellement effacer quelque chose');
});
