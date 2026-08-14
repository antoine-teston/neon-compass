// Retranscrit la carte communautaire GTA VI (State of Leonida, YANIS v14) dans
// l'identité Neon Compass. Même principe que gtav-restyle.mjs : classification
// par teinte puis modulation dans chaque classe par luminance relative.

const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];

// NCColor.swift — palette cible Neon Compass
const NIGHT_SKY = hex('#0A081A');
const MAGENTA   = hex('#FF3388');
const VIOLET    = hex('#8C33F2');
const ORANGE    = hex('#FF8C40');
const CYAN      = hex('#26F2F2');
const SEA_SHALLOW = hex('#3A28A0');
const LAND_DARK   = hex('#1E1547');
const LAND_LIGHT  = hex('#3A2590');

const WATER = 1, ROAD = 2, URBAN = 3, LAND = 4, GRID = 5, DARK = 6, SAND = 7, STREET = 8, LABEL = 9;

function classify(r, g, b) {
  const lum = (r + g + b) / 3;
  const sat = Math.max(r, g, b) - Math.min(r, g, b);

  // Labels blancs de localités — la signature la plus nette
  if (r > 240 && g > 240 && b > 240) return LABEL;

  // Sombre — avec exception pour l'océan assombri par la grille de coordonnées,
  // les routes rouge sombre et les rues grises urbaines.
  if (lum < 100) {
    if (b > 130 && b > r + 50 && r < 90 && g < 160) return WATER;
    if (r > 125 && r > g + 50 && r > b + 50) return ROAD;
    if (sat < 20 && lum > 40) return STREET;
    return DARK;
  }

  // Eau profonde : canal bleu largement dominant
  if (b > 200 && b > r + 40 && b > g) return WATER;
  if (b > 180 && r < 100 && g < 160) return WATER;
  if (b > 130 && b > r + 50 && r < 100 && g < 160) return WATER;

  // Eau peu profonde : bleu pâle, tous canaux élevés, saturation modérée.
  // Distingué du bâti pastel par b strictement dominant et sat < 80.
  if (lum > 140 && b > r && b > g && sat < 80) return WATER;

  // Fond de carte hors géographie : bleu-gris sombre rgb(~95,85,125)
  if (b > r && b > g && lum < 110 && sat < 50) return WATER;

  // Rues et asphalte : gris neutre à luminance moyenne (rues sombres déjà
  // couvertes dans le bloc lum < 100). Le bâti pâle reste au-dessus de 195.
  if (sat < 12 && lum < 195) return STREET;

  // Plages saumon rgb(~255,176,128) : b=128 rate le seuil sable historique et
  // tombait dans ROAD → liseré cyan électrique le long des côtes.
  if (r > 200 && g > 140 && b < 160 && r > b + 80 && lum > 150) return SAND;

  // Routes/frontières : rouge dominant. Les autoroutes YANIS sont un rouge
  // terne rgb(~156-182,84,84) — la même famille que la grille de coordonnées,
  // qui est désormais effacée par position (bandes axiales) avant le restylage.
  if (r > 140 && r > g + 55 && r > b + 55) return ROAD;

  // Terre/végétation : vert dominant (strict puis élargi aux forêts)
  if (g > 200 && g > r + 50 && g > b + 50) return LAND;
  if (g > 150 && g > r + 30 && g > b + 30 && sat > 50) return LAND;

  // Sable/plage : luminance élevée, teinte chaude
  if (r > 180 && g > 150 && b < 120 && lum > 160) return SAND;

  // Urbain : les trois canaux élevés, pastels saturés
  if (lum > 120 && sat > 40) return URBAN;

  // Désaturé à luminance moyenne → encore du bâti
  if (lum > 90 && sat < 40) return URBAN;

  return LAND;
}

const mix = (a, b, t) => [
  Math.round(a[0] + (b[0] - a[0]) * t),
  Math.round(a[1] + (b[1] - a[1]) * t),
  Math.round(a[2] + (b[2] - a[2]) * t),
];
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const norm = (v, lo, hi) => clamp01((v - lo) / (hi - lo));

function target(cls, r, g, b) {
  const lum = (r + g + b) / 3;
  switch (cls) {
    case WATER: {
      // Plafonné à 0.8 : le palier max collé à la côte formait un halo trop
      // marqué — le contour reste lisible mais discret.
      const t = norm(lum, 60, 240);
      const step = Math.min(0.8, Math.round(t * 10) / 10);
      return mix(NIGHT_SKY, SEA_SHALLOW, step);
    }
    case ROAD:   return mix(mix(LAND_LIGHT, CYAN, 0.75), CYAN, norm(lum, 90, 230));
    case URBAN:  return mix(LAND_DARK, mix(LAND_LIGHT, VIOLET, 0.4), norm(lum, 80, 220));
    case LAND:   return mix(LAND_DARK, LAND_LIGHT, norm(g, 120, 255));
    case SAND:   return mix(LAND_LIGHT, mix(LAND_LIGHT, ORANGE, 0.3), norm(lum, 160, 240));
    case STREET: return mix(LAND_DARK, CYAN, 0.45 + norm(lum, 40, 195) * 0.35);
    case LABEL:  return [235, 228, 255];
    case GRID:   return NIGHT_SKY;
    case DARK:   return mix(NIGHT_SKY, LAND_DARK, norm(lum, 0, 100));
    default:     return LAND_DARK;
  }
}

/**
 * @param data   buffer RGB (3 canaux, sans alpha)
 * @param scale  facteur d'échelle par rapport au z5, où il vaut 1. Les
 *               constantes géométriques (tailles de boîte, aires) en dépendent ;
 *               les seuils de couleur et les rapports, jamais.
 * @param frame  place du tampon dans l'image globale : `{x, y}` son origine,
 *               `{w, h}` les dimensions globales. Par défaut le tampon EST
 *               l'image, ce qui rend le comportement identique à l'appel à
 *               trois arguments. Seule la rose des vents, repérée en fraction
 *               de l'image entière, en a besoin.
 * @param count  fenêtre de COMPTAGE, en coordonnées du TAMPON (pas de l'image
 *               globale). Seuls les pixels qui y tombent alimentent
 *               `labelUnified`, `gridErased`, `oceanCleaned`, `compassBoosted`
 *               et l'histogramme `stats` — dénominateur compris. Par défaut le
 *               tampon entier. Un appelant fenêtré doit y passer son CŒUR :
 *               sinon les halos se comptent deux fois et `stats` se calcule sur
 *               un dénominateur gonflé. Le rendu, lui, ne dépend jamais de ce
 *               paramètre.
 * @returns nouveau buffer RGB restylé + stats
 */
export function restyle(data, width, height, scale = 1,
                        frame = { x: 0, y: 0, w: width, h: height },
                        count = { x: 0, y: 0, w: width, h: height }) {
  const n = width * height;
  const cls = new Uint8Array(n);
  const out = Buffer.allocUnsafe(n * 3);
  const cX1 = count.x + count.w, cY1 = count.y + count.h;
  const inCount = (x, y) => x >= count.x && x < cX1 && y >= count.y && y < cY1;

  const cache = new Map();

  for (let i = 0; i < n; i++) {
    const o = i * 3;
    const r = data[o], g = data[o + 1], b = data[o + 2];
    const key = (r << 16) | (g << 8) | b;
    let hit = cache.get(key);
    if (hit === undefined) {
      const c = classify(r, g, b);
      const t = target(c, r, g, b);
      hit = [c, t[0], t[1], t[2]];
      cache.set(key, hit);
    }
    cls[i] = hit[0];
    out[o] = hit[1]; out[o + 1] = hit[2]; out[o + 2] = hit[3];
  }

  // Uniformisation des libellés : tous les noms de localités passent en
  // blanc-lavande, pas seulement le texte blanc pur. Trois familles de texte
  // survivent au classificateur avec la couleur de leur classe hôte : les noms
  // de districts rouge VIF (rgb ~240-250,80-120,70-120 — nettement plus clair
  // que les autoroutes brique), les petits libellés gris (le même gris que les
  // rues), et les noms de parcs vert-blanc pâle (rgb ~224-240,232-240,208-216).
  // La couleur seule ne sépare pas ces textes de leur classe hôte : la
  // différence est géométrique. Un glyphe est une petite composante connexe
  // isolée (son halo blanc le détache des rues) ; le réseau routier est une
  // composante géante ; un bâtiment gris ou un tiret de limite de comté
  // REMPLIT sa boîte englobante, là où un glyphe est fait de traits.
  // Famille du candidat : 0 = non, 1 = gris rue, 2 = rouge vif, 3 = pâle.
  // Les plafonds diffèrent par famille : les glyphes denses sans contre-forme
  // (le M ou le I plein de MOUNT KALAGA) remplissent leur boîte à 0.67-1.0,
  // donc le plafond de remplissage qui écarte les bâtiments gris ne peut pas
  // s'appliquer aux textes pâles et rouges — seuls les gris en ont besoin.
  const labelFamily = (i) => {
    const o3 = i * 3;
    const r = data[o3], g = data[o3 + 1], b = data[o3 + 2];
    if (cls[i] === STREET) return 1;
    if (cls[i] === ROAD) return r > 210 && r - g > 110 ? 2 : 0;
    const l = (r + g + b) / 3;
    const s = Math.max(r, g, b) - Math.min(r, g, b);
    return l > 195 && s >= 13 && s <= 45 && g >= r && r > b ? 3 : 0;
  };
  const AREA_MIN = Math.round(12 * scale * scale);
  const AREA_MAX = Math.round(12000 * scale * scale);
  const BOX_W = Math.round(300 * scale);
  const BOX_H_GREY = Math.round(60 * scale), BOX_H_OTHER = Math.round(130 * scale);
  const ROAD_TOUCH = Math.round(3 * scale);
  const seen = new Uint8Array(n);
  const stack = [], members = [];
  let labelUnified = 0;
  for (let start = 0; start < n; start++) {
    if (seen[start] || !labelFamily(start)) continue;
    stack.length = 0; members.length = 0;
    stack.push(start); seen[start] = 1;
    let area = 0, minX = width, maxX = 0, minY = height, maxY = 0;
    let fam = 0;
    while (stack.length > 0) {
      const i = stack.pop();
      area++;
      if (members.length <= AREA_MAX) members.push(i);
      const f = labelFamily(i);
      if (f > fam) fam = f;
      const x = i % width, y = (i / width) | 0;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (x > 0 && !seen[i - 1] && labelFamily(i - 1)) { seen[i - 1] = 1; stack.push(i - 1); }
      if (x < width - 1 && !seen[i + 1] && labelFamily(i + 1)) { seen[i + 1] = 1; stack.push(i + 1); }
      if (y > 0 && !seen[i - width] && labelFamily(i - width)) { seen[i - width] = 1; stack.push(i - width); }
      if (y < height - 1 && !seen[i + width] && labelFamily(i + width)) { seen[i + width] = 1; stack.push(i + width); }
    }
    const bw = maxX - minX + 1, bh = maxY - minY + 1;
    if (area < AREA_MIN || area > AREA_MAX) continue;
    // Gris : hauteur d'une ligne de texte (écarte l'entrepôt hachuré) et
    // remplissage de glyphe (écarte les bâtiments pleins). Pâle/rouge : pas de
    // plafond de remplissage, les tirets de comté sont effacés en amont.
    const boxH = fam === 1 ? BOX_H_GREY : BOX_H_OTHER;
    if (bw > BOX_W || bh > boxH) continue;
    if (fam === 1 && area / (bw * bh) > 0.62) continue;
    // Un libellé gris ne touche jamais le réseau ROAD (son halo l'en
    // détache) ; un tablier de pont gris si, à ses deux extrémités. Garde
    // réservée à la famille grise : une lettre rouge vive est cernée de son
    // propre anticrénelage classé ROAD (sous le seuil vif) et se
    // disqualifierait elle-même.
    if (fam === 1) {
      let roadTouch = 0;
      for (const i of members) {
        const x = i % width;
        if ((x > 0 && cls[i - 1] === ROAD) || (x < width - 1 && cls[i + 1] === ROAD)
          || (i >= width && cls[i - width] === ROAD) || (i < n - width && cls[i + width] === ROAD)) {
          if (++roadTouch > ROAD_TOUCH) break;
        }
      }
      if (roadTouch > ROAD_TOUCH) continue;
    }
    for (const i of members) {
      cls[i] = LABEL;
      const o3 = i * 3;
      out[o3] = 235; out[o3 + 1] = 228; out[o3 + 2] = 255;
      // Compté membre par membre, et non `+= area` : une composante à cheval
      // sur le bord du cœur ne doit compter que par la part qui y tombe.
      // Fenêtre par défaut, members.length === area, donc valeur inchangée.
      if (inCount(i % width, (i / width) | 0)) labelUnified++;
    }
  }

  // Rayon de voisinage. Tous les tests de voisinage qui suivent — la mesure
  // d'épaisseur des traits de grille, les sondes d'angle et le carré du
  // nettoyage océan — mesurent la MÊME distance physique et doivent donc
  // s'échelonner ensemble. Un rayon laissé à 2 alors que le trait fait 4 px de
  // large rendrait le test d'épaisseur toujours faux, et la passe cesserait
  // d'effacer quoi que ce soit, sans erreur.
  const R = Math.max(1, Math.round(2 * scale));           // 2 à z5, 4 à z6
  // 80 % du voisinage (2R+1)², et non une longueur : c'est un pourcentage
  // déguisé, qui retombe sur 20 quand R vaut 2.
  const OCEAN_MIN = Math.round(0.8 * (2 * R + 1) ** 2);

  // Lignes de grille fines : les traits rouges fins (1-2 px à z5) de la grille
  // de coordonnées source classifiés ROAD → CYAN. On détecte les ROAD
  // « minces » et on les reclasse selon le voisin dominant.
  let gridErased = 0;
  for (let y = R; y < height - R; y++) {
    for (let x = R; x < width - R; x++) {
      const i = y * width + x;
      if (cls[i] !== ROAD) continue;
      // Rouge vif (r-g ≥ 115) = vraie route, même fine — seuls les résidus
      // ternes de la grille sont candidats à l'effacement.
      if (data[i * 3] - data[i * 3 + 1] >= 115) continue;
      const thin = (cls[(y - R) * width + x] !== ROAD && cls[(y + R) * width + x] !== ROAD) ||
                   (cls[y * width + (x - R)] !== ROAD && cls[y * width + (x + R)] !== ROAD);
      if (!thin) continue;
      const nb = [cls[i - 1], cls[i + 1], cls[i - width], cls[i + width]].filter(c => c !== ROAD);
      const repl = nb.length > 0 ? nb[0] : LAND;
      cls[i] = repl;
      const o = i * 3;
      if (repl === WATER || repl === DARK) {
        out[o] = NIGHT_SKY[0]; out[o + 1] = NIGHT_SKY[1]; out[o + 2] = NIGHT_SKY[2];
      } else {
        const t = target(repl, data[o], data[o + 1], data[o + 2]);
        out[o] = t[0]; out[o + 1] = t[1]; out[o + 2] = t[2];
      }
      if (inCount(x, y)) gridErased++;
    }
  }

  // Nettoyage océan : résidus de grille isolés (bords AA, labels intérieurs).
  // Seuil 80 % eau/grille dans le voisinage (2R+1)², une seule passe.
  // La rose des vents est protégée.
  let oceanCleaned = 0;
  for (let y = R; y < height - R; y++) {
    for (let x = R; x < width - R; x++) {
      const i = y * width + x;
      if (cls[i] === WATER || cls[i] === GRID || cls[i] === LABEL) continue;
      if (x + frame.x >= frame.w * 0.82 && y + frame.y >= frame.h * 0.79) continue;
      const c00 = cls[(y - R) * width + (x - R)], c01 = cls[(y - R) * width + (x + R)];
      const c10 = cls[(y + R) * width + (x - R)], c11 = cls[(y + R) * width + (x + R)];
      const isW = c => c === WATER || c === GRID;
      if (!isW(c00) && !isW(c01) && !isW(c10) && !isW(c11)) continue;
      let w = 0;
      for (let dy = -R; dy <= R; dy++)
        for (let dx = -R; dx <= R; dx++) {
          const nc = cls[(y + dy) * width + (x + dx)];
          if (nc === WATER || nc === GRID) w++;
        }
      if (w < OCEAN_MIN) continue;
      cls[i] = WATER;
      const o = i * 3;
      out[o] = NIGHT_SKY[0]; out[o + 1] = NIGHT_SKY[1]; out[o + 2] = NIGHT_SKY[2];
      if (inCount(x, y)) oceanCleaned++;
    }
  }

  // Rose des vents : rehausser le contraste. On détecte les éléments de la rose
  // par comparaison avec l'océan source (tout pixel significativement différent
  // du bleu océan est un élément de la rose) et on les rend en VIOLET lumineux.
  // Repérée en fraction de l'IMAGE, pas du tampon : une fenêtre ne doit pas
  // s'en fabriquer une à elle. Les coordonnées sont celles du tampon, donc
  // possiblement hors de lui — les boucles s'en accommodent.
  const compassX0 = Math.floor(frame.w * 0.82) - frame.x;
  const compassY0 = Math.floor(frame.h * 0.79) - frame.y;
  let compassBoosted = 0;
  for (let y = Math.max(0, compassY0); y < height; y++) {
    for (let x = Math.max(0, compassX0); x < width; x++) {
      const i = y * width + x;
      const so = i * 3;
      const sr = data[so], sg = data[so + 1], sb = data[so + 2];
      const slum = (sr + sg + sb) / 3;
      // L'océan source dans cette zone est bleu sombre rgb(~44-60,~100-120,~164-176).
      // Tout ce qui s'en écarte nettement (plus lumineux, moins bleu, plus rouge)
      // est un élément graphique de la rose.
      const isOcean = sb > 130 && sb > sr + 40 && slum < 140;
      if (isOcean) continue;
      const o = i * 3;
      // Dégradé par luminance : le cœur de l'étoile (sombre) reste sombre-violet,
      // les labels blancs/gris deviennent violet vif.
      const t = norm(slum, 60, 240);
      const c = mix(mix(NIGHT_SKY, VIOLET, 0.6), VIOLET, t);
      out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2];
      cls[i] = URBAN; // empêche le flatten océan
      if (inCount(x, y)) compassBoosted++;
    }
  }

  // Histogramme sur la fenêtre de comptage, dénominateur compris : sur une
  // fenêtre à halo, `n` gonflerait les parts de ce que le halo contient.
  const counts = {};
  for (let y = count.y; y < cY1; y++)
    for (let x = count.x; x < cX1; x++) {
      const c = cls[y * width + x];
      counts[c] = (counts[c] ?? 0) + 1;
    }
  const nCount = count.w * count.h;
  const label = { [WATER]: 'eau', [ROAD]: 'axes', [URBAN]: 'bâti', [LAND]: 'terre', [GRID]: 'grille', [DARK]: 'sombre', [SAND]: 'sable', [STREET]: 'rues', [LABEL]: 'libellés' };
  const stats = Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => `${label[k] ?? k} ${(v / nCount * 100).toFixed(1)}%`)
    .join('  ');

  const ocean = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    if (cls[i] === WATER) { ocean[i] = 1; continue; }
    // GRID et LABEL comptent comme océan pour le crop : un libellé au large
    // (BAHIA HONDA KEY…) ne doit pas étirer le cadrage.
    if (cls[i] === GRID || cls[i] === LABEL) {
      const x = i % width, y = (i / width) | 0;
      if (x >= compassX0 && y >= compassY0) continue;
      ocean[i] = 1;
    }
  }

  // `colorsInWindow` : une taille de cache ne se ramène pas à un cœur — deux
  // fenêtres partagent des couleurs, et les sommer compterait double. Le nom
  // dit la portée pour que personne ne l'additionne.
  return { data: out, ocean, stats, colorsInWindow: cache.size, gridErased, oceanCleaned, compassBoosted, labelUnified };
}
