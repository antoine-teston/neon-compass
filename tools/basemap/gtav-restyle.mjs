// Retranscrit la carte de référence (aplats verts/beiges/bleus d'origine) dans
// l'identité Neon Compass. La cible n'est pas inventée : elle reprend
// island-placeholder.svg, qui fixe déjà le rendu carte validé — mer
// #0A081A -> #141033, terre #1E1547 -> #2A1B66, littoral magenta, axes cyan,
// secondaires orange. Les couleurs viennent de Core/DesignSystem/NCColor.swift.
//
// Approche : classification par teinte plutôt que remap de luminance globale.
// Une simple rampe de luminance donnerait la même couleur à l'océan et à la
// végétation (luminances voisines, 128 vs 160) et écraserait la carte. On
// classe donc chaque pixel, puis on module DANS sa classe par sa luminance
// relative — ce qui préserve l'ombrage du relief et la hiérarchie des routes.

const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];

// NCColor.swift
const NIGHT_SKY = hex('#0A081A');
const MAGENTA   = hex('#FF3388');
const VIOLET    = hex('#8C33F2');
const ORANGE    = hex('#FF8C40');
const CYAN      = hex('#26F2F2');
// Rampes de island-placeholder.svg
const SEA_SHALLOW = hex('#141033');
const LAND_DARK   = hex('#1E1547');
const LAND_LIGHT  = hex('#2A1B66');

// Tests « ce pixel est-il de l'eau ? », exportés parce que gtav-poi.mjs s'en
// sert pour rejeter les objets tombant en mer. Les bornes [0,1] ne suffisent
// pas : le carré de carte contient beaucoup d'océan, donc des contenus hors
// carte (yachts, porte-avions, cargos, prologue, Cayo Perico) passent le test
// de bornes tout en flottant en pleine eau — ce qui se lit comme un bug.
// Après restylage les deux rampes sont franchement séparées (océan B ≤ 51,
// terre B ≥ 71) : la marge absorbe le downscale et la quantification en palette.
export const isOceanNC = (r, g, b) => b < 60 && r < 28;
export const isOceanRaw = (r, g, b) => b > r + 25 && b > 110;

const mix = (a, b, t) => [
  Math.round(a[0] + (b[0] - a[0]) * t),
  Math.round(a[1] + (b[1] - a[1]) * t),
  Math.round(a[2] + (b[2] - a[2]) * t),
];
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const norm = (v, lo, hi) => clamp01((v - lo) / (hi - lo));

// Classes. L'ordre de test compte : l'eau est franchement bleue, les
// routes/bâti franchement désaturés, le reste se départage sur la teinte.
const WATER = 1, ROAD = 2, URBAN = 3, SAND = 4, LAND = 5, TRAIL = 6, DARK = 7;

// Seuil routes/bâti mesuré sur l'image : la trame urbaine est à lum~210, les
// axes et le bâti dense à lum~244. La distribution des pixels désaturés est
// bimodale autour de 220, d'où la coupure ici.
const ROAD_LUM = 232;

function classify(r, g, b) {
  const lum = (r + g + b) / 3;
  const sat = Math.max(r, g, b) - Math.min(r, g, b);
  if (b > r + 30 && b > 150) return WATER;
  if (lum < 110) return DARK;
  if (sat < 50) return lum >= ROAD_LUM ? ROAD : URBAN;
  if (r > g + 20 && r > b + 20) return TRAIL;      // voies ferrées, pistes
  if (r >= g && b < g - 25 && lum > 175) return SAND;
  if (g >= b) return LAND;
  return LAND;
}

function target(cls, r, g, b) {
  const lum = (r + g + b) / 3;
  switch (cls) {
    // L'océan profond de la source a peu de rouge, les hauts-fonds beaucoup :
    // r est donc un bon proxy de profondeur.
    case WATER: return mix(NIGHT_SKY, SEA_SHALLOW, norm(r, 8, 150));
    case ROAD:  return mix(mix(LAND_LIGHT, CYAN, 0.5), CYAN, norm(lum, ROAD_LUM, 255));
    case URBAN: return mix(mix(LAND_LIGHT, VIOLET, 0.12), mix(LAND_LIGHT, VIOLET, 0.42), norm(lum, 150, ROAD_LUM));
    case SAND:  return mix(LAND_LIGHT, mix(LAND_LIGHT, ORANGE, 0.3), norm(lum, 175, 235));
    case LAND:  return mix(LAND_DARK, LAND_LIGHT, norm(lum, 135, 200));
    case TRAIL: return mix(LAND_LIGHT, MAGENTA, 0.5);
    case DARK:  return mix(NIGHT_SKY, LAND_DARK, norm(lum, 0, 110));
    default:    return LAND_DARK;
  }
}

/**
 * @param data  buffer RGB (3 canaux, sans alpha)
 * @returns nouveau buffer RGB restylé
 */
export function restyle(data, width, height) {
  const n = width * height;
  const cls = new Uint8Array(n);
  const out = Buffer.allocUnsafe(n * 3);

  // Cache : la carte est en aplats, donc quelques dizaines de milliers de
  // couleurs distinctes seulement pour ~9,4 M pixels.
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

  // Littoral magenta — le trait qui signe le plus l'identité (le placeholder
  // l'a en stroke #FF3388). Marque tout pixel d'eau touchant une terre, puis
  // dilate d'un pixel pour que le trait survive au downscale vers 2048.
  const edge = new Uint8Array(n);
  const isLand = (c) => c !== WATER && c !== 0;
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const i = y * width + x;
      if (cls[i] !== WATER) continue;
      if (isLand(cls[i - 1]) || isLand(cls[i + 1]) || isLand(cls[i - width]) || isLand(cls[i + width])) edge[i] = 1;
    }
  }
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const i = y * width + x;
      if (edge[i] !== 1) continue;
      for (const d of [-1, 1, -width, width]) if (edge[i + d] === 0) edge[i + d] = 2;
    }
  }
  for (let i = 0; i < n; i++) {
    if (!edge[i]) continue;
    const o = i * 3;
    // Le trait dilaté est plus discret que le trait source : dégradé vers
    // l'eau plutôt qu'un liseré de 2 px pleins.
    const t = edge[i] === 1 ? 0.85 : 0.4;
    const c = mix([out[o], out[o + 1], out[o + 2]], MAGENTA, t);
    out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2];
  }

  const counts = {};
  for (let i = 0; i < n; i++) counts[cls[i]] = (counts[cls[i]] ?? 0) + 1;
  const label = { [WATER]: 'eau', [ROAD]: 'axes', [URBAN]: 'bâti', [SAND]: 'sable', [LAND]: 'terre', [TRAIL]: 'rail', [DARK]: 'sombre' };
  const stats = Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => `${label[k] ?? k} ${(v / n * 100).toFixed(1)}%`)
    .join('  ');

  return { data: out, stats, colors: cache.size };
}
