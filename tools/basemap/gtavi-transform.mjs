// Transformation de la carte communautaire GTA VI (YANIS v14) : tout ce qui
// s'applique au brut assemblé avant l'encodage — effacement du panneau de
// légende, suppression des limites de comté en tirets, effacement de la grille
// de coordonnées, restylage Neon Compass, aplatissement de l'océan profond.
//
// Ce traitement vivait dans gtavi-map.mjs, câblé sur l'image entière et sur les
// constantes du z5. Il est ici déplacé tel quel, mais paramétré par :
//   - une FENÊTRE (`win`) : la région de l'image globale que porte le tampon ;
//   - un CŒUR (`core`) : la sous-région de la fenêtre dont le résultat compte ;
//   - une ÉCHELLE, déduite de la largeur globale : `scale = full.w / REF`.
//
// Toute constante géométrique est exprimée à l'échelle du z5, où le facteur
// vaut exactement 1 — ce qui rend la non-régression exacte par construction.
//
// Le découpage en quadrants n'est exact que parce que chaque passe est locale à
// un halo près. Une seule ne l'est pas — le sondage de la grille de
// coordonnées, qui somme des colonnes et des lignes entières — et elle est pour
// cette raison coupée en deux : `gridProbe` accumule par cœur, `gridCenters`
// conclut globalement.

import { restyle } from './gtavi-restyle.mjs';

export const REF = 10240;   // La largeur du z5.

/// Le facteur d'échelle, et le contrôle qui empêche de se le fabriquer par
/// accident. `full` est la GÉOMÉTRIE DE RÉFÉRENCE, pas la taille du brut que
/// l'appelant a sous la main : le brut assemblé du z6 fait 79×256 = 20224 px,
/// et le prendre au mot donnerait scale = 1,975, donc E_PANEL = 5925 au lieu de
/// 6000 — une bande de 75 px de panneau de légende survivrait jusqu'au
/// classificateur. L'appelant COMPLÈTE sa source jusqu'à un multiple exact de
/// REF (20480 pour le z6) et passe cette dimension-là. On refuse tout ce qui
/// n'est pas un rapport entier dans un sens ou dans l'autre, plutôt que de
/// laisser le piège se refermer en silence.
function scaleOf(full) {
  if (!full || !Number.isInteger(full.w) || full.w <= 0) {
    throw new TypeError(`full.w doit être un entier positif, reçu ${full && full.w}`);
  }
  if (full.w % REF !== 0 && REF % full.w !== 0) {
    throw new RangeError(
      `full.w (${full.w}) doit être un multiple exact de REF (${REF}) — ` +
      `compléter la source jusqu'à ${Math.ceil(full.w / REF) * REF} avant d'appeler`);
  }
  return full.w / REF;
}

/// Un rectangle en coordonnées globales, ou une erreur bruyante. `core` n'a pas
/// de valeur par défaut sûre : le confondre avec un autre argument rendrait des
/// compteurs nuls sans rien signaler.
function checkRect(r, name) {
  if (!r || !Number.isFinite(r.x) || !Number.isFinite(r.y)
    || !Number.isFinite(r.w) || !Number.isFinite(r.h)) {
    throw new TypeError(`${name} doit être un rectangle {x, y, w, h} en coordonnées globales`);
  }
  return r;
}

/// La géométrie du panneau de légende, en coordonnées GLOBALES. Une seule
/// définition, parce que la carte restylée et la classic doivent effacer
/// exactement la même chose, à jamais.
export function legendMask(full) {
  const s = scaleOf(full);
  const E_PANEL = Math.round(3000 * s), E_BAND = Math.round(400 * s), E_RIGHT = Math.round(500 * s);
  return (gx, gy) =>
    gx < E_PANEL || gy < E_BAND || gy >= full.h - E_BAND || gx >= full.w - E_RIGHT;
}

/// Phase A : effacer la légende, puis supprimer les tirets de limite de comté.
/// Purement locale à la fenêtre. Écrit le résultat dans `rgb` sur place.
/// @param {Buffer} rgb    RGB de la fenêtre, win.w × win.h × 3 — MUTÉ sur place
/// @param {{x,y,w,h}} win position et taille de la fenêtre dans l'image globale
/// @param {{w,h}} full    géométrie de RÉFÉRENCE, multiple exact de REF ;
///        voir scaleOf() — ce n'est pas forcément la taille du brut assemblé
/// @param {{r,g,b}} ocean couleur d'effacement, échantillonnée sur la source
/// @param {{x,y,w,h}} core  la part de la fenêtre dont le résultat compte, en
///        coordonnées globales. Le TRAITEMENT porte sur toute la fenêtre, halo
///        compris — seuls les COMPTEURS de pixels s'y limitent, faute de quoi
///        les recouvrements se comptent deux fois et la somme sur quatre
///        quadrants ne vaut plus le traitement d'un bloc.
/// @param {Buffer|null} erasedOut  si fourni, reçoit une copie de la fenêtre
///        prise ENTRE l'effacement et la suppression des tirets — c'est
///        exactement ce que la version classic restitue.
/// @returns {{erased, dashCompsInWindow, dashTotal, dashSuppressed}}
///   erased, dashSuppressed  : pixels, comptés sur le CŒUR
///   dashCompsInWindow       : composantes, donc non ramenables à un cœur — un
///                             tiret à cheval appartient à deux fenêtres et la
///                             somme sur les quadrants n'a pas de sens
export function eraseAndDash(rgb, win, full, ocean, core, erasedOut = null) {
  const W = win.w, H = win.h;
  const scale = scaleOf(full);
  checkRect(core, 'core');
  const kx0 = core.x, kx1 = core.x + core.w, ky0 = core.y, ky1 = core.y + core.h;
  const inCore = (gx, gy) => gx >= kx0 && gx < kx1 && gy >= ky0 && gy < ky1;

  // Effacer le panneau de légende AVANT le restylage.
  // Le panneau (titre YANIS, légende, crédits, photos) est incrusté dans les
  // tuiles source avec un fond BLANC OPAQUE — il n'y a aucun contenu
  // géographique visible sous le panneau. On remplace TOUT pixel non-océan
  // dans la zone du panneau (profil mesuré) par la couleur océan.
  // L'océan réel sert de couleur d'effacement : classify() le reconnaît
  // désormais (b>130 && b>r+50 && r<100 && g<160 → WATER), et il tombe sur le
  // MÊME palier de dégradé que l'océan profond voisin. Le crop élargi vers
  // l'ouest peut donc inclure la zone effacée sans couture visible, dans le
  // rendu néon comme dans la version classic.
  const [oR, oG, oB] = [ocean.r, ocean.g, ocean.b];
  const inLegend = legendMask(full);
  let erased = 0;
  for (let y = 0; y < H; y++) {
    const gy = win.y + y;
    for (let x = 0; x < W; x++) {
      const gx = win.x + x;
      if (!inLegend(gx, gy)) continue;
      const o = (y * W + x) * 3;
      rgb[o] = oR; rgb[o + 1] = oG; rgb[o + 2] = oB;
      if (inCore(gx, gy)) erased++;
    }
  }

  // La version classic reprend l'effacement (couleur océan réelle) : le crop
  // élargi vers l'ouest inclut l'ancienne zone du panneau YANIS. La grille de
  // coordonnées, elle, reste dans la classic — elle fait partie de la source.
  // La suppression des tirets aussi : c'est ici, et pas après, que la copie se
  // prend.
  if (erasedOut) erasedOut.set(rgb);

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
  const D_MARGIN = Math.round(3 * scale);       // marge de balayage
  const D_X0 = Math.round(3005 * scale);        // début du balayage, hors panneau
  const A_MIN = Math.round(30 * scale * scale);
  const A_MAX = Math.round(1500 * scale * scale);
  const T_THICK = Math.round(12 * scale);       // épaisseur maximale d'un tiret
  const R_COLL = Math.round(130 * scale);       // rayon de colinéarité
  const T_PERP = Math.round(9 * scale);         // tolérance perpendiculaire
  const H_DASH = Math.round(2 * scale);         // halo d'anticrénelage
  const F_REACH = Math.round(15 * scale);       // portée de remplissage
  const F_BEST = Math.round(20 * scale);

  // Bornes de balayage et de propagation, en coordonnées de FENÊTRE : le
  // prédicat est global, la fenêtre le borne.
  const bx0 = Math.max(0, D_MARGIN - win.x), bx1 = Math.min(W, full.w - D_MARGIN - win.x);
  const by0 = Math.max(0, D_MARGIN - win.y), by1 = Math.min(H, full.h - D_MARGIN - win.y);
  const sx0 = Math.max(0, D_X0 - win.x), sx1 = bx1;
  const sy0 = by0, sy1 = by1;

  const isWarm = (o) => rgb[o] > 170 && rgb[o] - rgb[o + 1] >= 70 && rgb[o] - rgb[o + 2] >= 70;
  const dashSeen = new Uint8Array(W * H);
  const dashes = [];
  const dStack = [];
  for (let y = sy0; y < sy1; y++) {
    for (let x = sx0; x < sx1; x++) {
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
        if (comp.length <= A_MAX) comp.push(i);
        const px = i % W, py = (i / W) | 0;
        sx += px; sy += py;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (!dx && !dy) continue;
            const nx = px + dx, ny = py + dy;
            if (nx < bx0 || nx >= bx1 || ny < by0 || ny >= by1) continue;
            const j = ny * W + nx;
            if (!dashSeen[j] && isWarm(j * 3)) { dashSeen[j] = 1; dStack.push(j); }
          }
        }
      }
      if (area < A_MIN || area > A_MAX) continue;
      const cx = sx / comp.length, cy = sy / comp.length;
      let mxx = 0, myy = 0, mxy = 0;
      for (const i of comp) {
        const dx = (i % W) - cx, dy = ((i / W) | 0) - cy;
        mxx += dx * dx; myy += dy * dy; mxy += dx * dy;
      }
      mxx /= comp.length; myy /= comp.length; mxy /= comp.length;
      const tr = mxx + myy, det = Math.sqrt((mxx - myy) ** 2 + 4 * mxy * mxy);
      const l1 = (tr + det) / 2, l2 = (tr - det) / 2;
      if (Math.sqrt(12 * Math.max(0, l2)) > T_THICK || l2 / l1 > 0.25) continue;
      const theta = 0.5 * Math.atan2(2 * mxy, mxx - myy);
      dashes.push({ cx, cy, ux: Math.cos(theta), uy: Math.sin(theta), comp });
    }
  }
  // Confirmation en deux temps : ≥2 voisins colinéaires, puis PROPAGATION.
  // Un tiret de bout de ligne n'a qu'un seul voisin dans les 130 px (la ligne
  // s'arrête là), mais si ce voisin est lui-même confirmé, le tiret appartient
  // à la même limite — itéré jusqu'au point fixe, sinon chaque extrémité de
  // ligne laisse un orphelin que l'uniformisation des libellés repeint en blanc.
  // C'est la seule passe dont le halo ne borne pas la portée : la propagation
  // court sur toute la longueur d'une limite de comté. L'écart résiduel qu'elle
  // laisse entre un traitement d'un bloc et un traitement par quadrants est
  // mesuré par gtavi-transform.test.mjs, pas postulé.
  const collinear = (d, e) => {
    const vx = e.cx - d.cx, vy = e.cy - d.cy;
    if (Math.hypot(vx, vy) > R_COLL) return false;
    if (Math.abs(vx * -d.uy + vy * d.ux) > T_PERP) return false;
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
  let dashCompsInWindow = 0, dashTotal = 0;
  for (let a = 0; a < dashes.length; a++) {
    if (!confirmed[a]) continue;
    const d = dashes[a];
    dashCompsInWindow++;
    for (const i of d.comp) {
      const px = i % W, py = (i / W) | 0;
      // Le tiret plus son halo d'anticrénelage (mélange chaud rose/orangé sur
      // fond vert ou gris, qui laisserait un fantôme du tiret sinon).
      for (let dy = -H_DASH; dy <= H_DASH; dy++) {
        for (let dx = -H_DASH; dx <= H_DASH; dx++) {
          const nx = px + dx, ny = py + dy;
          if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
          const j = ny * W + nx;
          if (dashPx[j]) continue;
          const jo = j * 3;
          if ((dx === 0 && dy === 0) || (rgb[jo] >= 120 && rgb[jo] - rgb[jo + 1] >= 25)) {
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
    const r = rgb[o], g = rgb[o + 1], b = rgb[o + 2];
    if (r > 210 && r - g > 110) return true;
    const l = (r + g + b) / 3, s = Math.max(r, g, b) - Math.min(r, g, b);
    return l > 195 && s >= 13 && s <= 45 && g >= r && r > b;
  };
  let dashSuppressed = 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      if (!dashPx[i]) continue;
      let bestDist = F_BEST, bestI = -1;
      for (const [dy, dx] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
        for (let d = 1; d <= F_REACH; d++) {
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
        rgb[o] = rgb[so]; rgb[o + 1] = rgb[so + 1]; rgb[o + 2] = rgb[so + 2];
        if (inCore(win.x + x, win.y + y)) dashSuppressed++;
      }
    }
  }

  return { erased, dashCompsInWindow, dashTotal, dashSuppressed };
}

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

/// Les deux garde-fous qui DISCRIMINENT : le pixel penche vers l'océan
/// assombri plutôt que vers l'océan pur, et il n'est pas l'océan pur.
const leansDark = (r, g, b) => dDark(r, g, b) < dPure(r, g, b) && dPure(r, g, b) > 150;

/// Le SONDAGE ne balaye que de l'océan pur : les deux garde-fous suffisent.
/// Pas de plafond — il n'y jouait aucun rôle à z5 (52+76 et centres
/// identiques de 400 à l'infini) et il rejetait le cœur du trait à z6, où
/// dDark vaut 413 contre 369 à z5, un seul niveau de gris d'écart.
const isDarkenedProbe = leansDark;

/// L'EFFACEMENT parcourt aussi la terre, où un gris sombre passerait
/// `leansDark`. Le plafond l'exclut : il reste, inchangé.
const isDarkened = (r, g, b) => leansDark(r, g, b) && dDark(r, g, b) < 400;

/// Fenêtres de sondage : océan pur au nord (l'île commence vers y≈1000) et à
/// l'ouest (x≈3400), en unités z5.
const probeWindow = (scale) => ({
  PY0: Math.round(420 * scale),
  PY1: Math.round(980 * scale),
  PX0: Math.round(3005 * scale),
  PX1: Math.round(3400 * scale),
});

/// Contribution de la fenêtre au sondage de la grille de coordonnées. À ne
/// calculer que sur le CŒUR, sinon les halos comptent deux fois.
/// @returns {{colHits: Uint32Array(full.w), rowHits: Uint32Array(full.h)}}
export function gridProbe(rgb, win, full, core) {
  const W = win.w;
  const scale = scaleOf(full);
  checkRect(core, 'core');
  const { PY0, PY1, PX0, PX1 } = probeWindow(scale);
  const M_RIGHT = Math.round(505 * scale);
  const M_VERT = Math.round(405 * scale);
  const colHits = new Uint32Array(full.w), rowHits = new Uint32Array(full.h);

  let y0 = Math.max(core.y, PY0), y1 = Math.min(core.y + core.h, PY1);
  let x0 = Math.max(core.x, PX0), x1 = Math.min(core.x + core.w, full.w - M_RIGHT);
  for (let gy = y0; gy < y1; gy++) {
    for (let gx = x0; gx < x1; gx++) {
      const o = ((gy - win.y) * W + (gx - win.x)) * 3;
      if (isDarkenedProbe(rgb[o], rgb[o + 1], rgb[o + 2])) colHits[gx]++;
    }
  }
  y0 = Math.max(core.y, M_VERT); y1 = Math.min(core.y + core.h, full.h - M_VERT);
  x0 = Math.max(core.x, PX0); x1 = Math.min(core.x + core.w, PX1);
  for (let gy = y0; gy < y1; gy++) {
    for (let gx = x0; gx < x1; gx++) {
      const o = ((gy - win.y) * W + (gx - win.x)) * 3;
      if (isDarkenedProbe(rgb[o], rgb[o + 1], rgb[o + 2])) rowHits[gy]++;
    }
  }
  return { colHits, rowHits };
}

/// Les centres de traits, depuis les contributions sommées. Global.
/// @returns {{colCenter: Int32Array(full.w), rowCenter: Int32Array(full.h), nCols, nRows}}
export function gridCenters(colHits, rowHits, full) {
  const scale = scaleOf(full);
  const { PY0, PY1, PX0, PX1 } = probeWindow(scale);
  const SPREAD = Math.round(5 * scale);
  const colCenter = new Int32Array(full.w).fill(-1), rowCenter = new Int32Array(full.h).fill(-1);
  let nCols = 0, nRows = 0;
  for (let x = 0; x < full.w; x++) {
    if (colHits[x] < (PY1 - PY0) * 0.4) continue;
    nCols++;
    for (let d = -SPREAD; d <= SPREAD; d++) if (x + d >= 0 && x + d < full.w) colCenter[x + d] = x;
  }
  for (let y = 0; y < full.h; y++) {
    if (rowHits[y] < (PX1 - PX0) * 0.4) continue;
    nRows++;
    for (let d = -SPREAD; d <= SPREAD; d++) if (y + d >= 0 && y + d < full.h) rowCenter[y + d] = y;
  }
  return { colCenter, rowCenter, nCols, nRows };
}

/// Phase B : effacer la grille, restyler, aplatir l'océan profond. Locale à la
/// fenêtre, mais lit les centres GLOBAUX.
///
/// ATTENTION : `rgb` est MUTÉ SUR PLACE — l'effacement de la grille y réécrit
/// les pixels avant le restylage. L'appelant qui a besoin du brut d'origine en
/// garde une copie AVANT l'appel.
///
/// @param {Buffer} rgb  RGB de la fenêtre, win.w × win.h × 3 — muté sur place
/// @param {{x,y,w,h}} win  position et taille de la fenêtre dans l'image globale
/// @param {{w,h}} full  géométrie de RÉFÉRENCE, multiple exact de REF
/// @param {{x,y,w,h}} core  la région à rendre, en coordonnées globales
/// @param {{colCenter, rowCenter}} centers  le résultat de gridCenters
/// @returns un objet à 11 champs :
///   data            : Buffer RGB restylé du CŒUR seul, core.w × core.h × 3
///   ocean           : Uint8Array(core.w × core.h), 1 si le pixel est de l'eau
///   bbox            : {minX, maxX, minY, maxY} des pixels non-océan du cœur,
///                     en coordonnées GLOBALES, ou null si le cœur est tout
///                     océan. Les bbox de plusieurs cœurs s'unissent donc
///                     directement, sans décalage à appliquer.
///   stats           : chaîne de pourcentages par classe, calculée sur le CŒUR
///   gridTotal       : pixels de grille détectés, sur le cœur
///   gridSuppressed  : pixels de grille remplacés, sur le cœur
///   flattened       : pixels d'océan profond ramenés à NIGHT_SKY, sur le cœur
///   labelUnified    : pixels de libellé uniformisés, sur le cœur
///   gridErased      : pixels d'axe fin reclassés, sur le cœur
///   oceanCleaned    : pixels isolés d'océan nettoyés, sur le cœur
///   colorsInWindow  : couleurs source distinctes — sur la FENÊTRE, halo
///                     compris. Ne pas sommer sur plusieurs fenêtres.
export function gridAndStyle(rgb, win, full, core, centers) {
  const W = win.w, H = win.h;
  const scale = scaleOf(full);
  checkRect(core, 'core');
  const kx0 = core.x, kx1 = core.x + core.w, ky0 = core.y, ky1 = core.y + core.h;
  const inCore = (gx, gy) => gx >= kx0 && gx < kx1 && gy >= ky0 && gy < ky1;
  const { colCenter, rowCenter } = centers;

  // Dans les bandes : test BILATÉRAL. Les deux références à ±8 px du CENTRE
  // du trait (hors trait et hors anticrénelage) doivent être d'accord entre
  // elles (≤30 par canal — le fond traverse la bande), et le pixel doit être
  // assombri par rapport à leur moyenne : somme des écarts 20..150, aucun
  // canal plus clair de >12. La grille assombrit de ~34 sur l'océan et ~94
  // sur la terre ; un texte ou une rue sombre qui croise la bande dévie de
  // bien plus (>240) et est épargné, une lisière de forêt aussi (~162).
  // Le rouge terne (grille sur fond clair) et l'océan assombri restent des
  // détections directes, sans référence.
  const G_REF = Math.round(8 * scale);
  const F_REACH = Math.round(15 * scale);
  const F_BEST = Math.round(20 * scale);
  // Les références sont globales ; la fenêtre les borne. Le halo les couvre
  // toutes pour un pixel du cœur — G_REF est de deux ordres au-dessous.
  const lx = (gx) => { const v = gx - win.x; return v < 0 ? 0 : v >= W ? W - 1 : v; };
  const ly = (gy) => { const v = gy - win.y; return v < 0 ? 0 : v >= H ? H - 1 : v; };

  const isGridPx = new Uint8Array(W * H);
  let gridTotal = 0;
  for (let y = 0; y < H; y++) {
    const gy = win.y + y;
    const rc = rowCenter[gy];
    for (let x = 0; x < W; x++) {
      const cc = colCenter[win.x + x];
      if (cc < 0 && rc < 0) continue;
      const o = (y * W + x) * 3;
      const pr = rgb[o], pg = rgb[o + 1], pb = rgb[o + 2];
      const lum = (pr + pg + pb) / 3;
      let hit = (pr > 150 && pr > pg + 30 && pb < 130 && lum < 160) || isDarkened(pr, pg, pb);
      if (!hit) {
        const aO = cc >= 0 ? (y * W + lx(Math.max(0, cc - G_REF))) * 3
                           : (ly(Math.max(0, rc - G_REF)) * W + x) * 3;
        const bO = cc >= 0 ? (y * W + lx(Math.min(full.w - 1, cc + G_REF))) * 3
                           : (ly(Math.min(full.h - 1, rc + G_REF)) * W + x) * 3;
        if (Math.abs(rgb[aO] - rgb[bO]) <= 30
          && Math.abs(rgb[aO + 1] - rgb[bO + 1]) <= 30
          && Math.abs(rgb[aO + 2] - rgb[bO + 2]) <= 30) {
          const dr = ((rgb[aO] + rgb[bO]) >> 1) - pr;
          const dg = ((rgb[aO + 1] + rgb[bO + 1]) >> 1) - pg;
          const db = ((rgb[aO + 2] + rgb[bO + 2]) >> 1) - pb;
          const dsum = dr + dg + db;
          hit = dr >= -12 && dg >= -12 && db >= -12 && dsum >= 20 && dsum <= 150;
        }
      }
      if (hit) {
        isGridPx[y * W + x] = 1;
        if (inCore(win.x + x, gy)) gridTotal++;
      }
    }
  }
  let gridSuppressed = 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      if (!isGridPx[i]) continue;
      let bestDist = F_BEST, bestI = -1;
      for (const [dy, dx] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
        for (let d = 1; d <= F_REACH; d++) {
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
        rgb[o] = rgb[so]; rgb[o + 1] = rgb[so + 1]; rgb[o + 2] = rgb[so + 2];
        if (inCore(win.x + x, win.y + y)) gridSuppressed++;
      }
    }
  }

  // La fenêtre de comptage de restyle() est le cœur, en coordonnées du tampon.
  // Fenêtre entière, elle vaut le tampon : c'est ce qui garde le z5 exact.
  const styled = restyle(rgb, W, H, scale,
    { x: win.x, y: win.y, w: full.w, h: full.h },
    { x: core.x - win.x, y: core.y - win.y, w: core.w, h: core.h });

  // Aplatir l'océan profond à NIGHT_SKY exact. Le restylage quantifie
  // désormais le dégradé eau en 11 paliers, donc seuls les pixels les plus
  // sombres (proches de NIGHT_SKY) sont unifiés — le gradient côtier est
  // préservé.
  //
  // Le même balayage prélève le cœur et relève la boîte englobante de l'île.
  // Le relevé exclut les zones d'effacement (panneau, labels) pour éviter les
  // faux bords créés par la dilatation du trait de côte.
  const NS = [0x0A, 0x08, 0x1A];
  const SL = Math.round(3100 * scale), ST = Math.round(450 * scale);
  const SR = Math.round(500 * scale), SB = Math.round(450 * scale);
  const data = Buffer.allocUnsafe(core.w * core.h * 3);
  const ocean = new Uint8Array(core.w * core.h);
  let flattened = 0;
  let minX = full.w, maxX = -1, minY = full.h, maxY = -1;
  for (let cy = 0; cy < core.h; cy++) {
    const gy = core.y + cy;
    const wy = gy - win.y;
    for (let cx = 0; cx < core.w; cx++) {
      const gx = core.x + cx;
      const si = wy * W + (gx - win.x), so = si * 3;
      const di = cy * core.w + cx, dO = di * 3;
      let r = styled.data[so], g = styled.data[so + 1], b = styled.data[so + 2];
      if (styled.ocean[si]) {
        ocean[di] = 1;
        const dr = r - NS[0], dg = g - NS[1], db = b - NS[2];
        if (dr * dr + dg * dg + db * db <= 50) {
          r = NS[0]; g = NS[1]; b = NS[2];
          flattened++;
        }
      } else if (gy >= ST && gy < full.h - SB && gx >= SL && gx < full.w - SR) {
        if (gx < minX) minX = gx;
        if (gx > maxX) maxX = gx;
        if (gy < minY) minY = gy;
        if (gy > maxY) maxY = gy;
      }
      data[dO] = r; data[dO + 1] = g; data[dO + 2] = b;
    }
  }
  const bbox = maxX < 0 ? null : { minX, maxX, minY, maxY };

  return {
    data, ocean, bbox,
    stats: styled.stats, gridTotal, gridSuppressed, flattened,
    labelUnified: styled.labelUnified, gridErased: styled.gridErased,
    oceanCleaned: styled.oceanCleaned,
    colorsInWindow: styled.colorsInWindow,
  };
}
