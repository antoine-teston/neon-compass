// Géoréférencement de la carte de référence GTA V — source unique de vérité,
// partagée par gtav-map.mjs (qui rend l'image) et gtav-poi.mjs (qui place les
// pins). Les deux DOIVENT être régénérés ensemble après toute modif ici :
// changer FRACTION ou WORLD_FIT sans refaire l'image désaligne tous les pins.
//
// Pourquoi une carte GTA V dans un projet GTA VI : aucune carte officielle
// GTA VI n'existe encore (tous les POI de content/poi/ ont position: null),
// donc le moteur de carte n'a jamais été exercé sur des données denses. Cette
// carte-là sert de fixture à l'échelle réelle.

export const TILE = 256;
export const TILE_BASE = 'https://s3-eu-west-1.amazonaws.com/gtavmap/tiles';
export const STYLES = ['atlas', 'satellite', 'road'];
export const MIN_ZOOM = 3;
export const MAX_ZOOM = 7; // z8 répond 403

// La carte occupe le coin haut-gauche du monde Web Mercator, 3/8 sur chaque
// axe. Mesuré en scannant la grille de tuiles : contenu sur x 0..2 / y 0..2 à
// z3 et 0..5 / 0..5 à z4 — cohérent d'un niveau à l'autre, donc ce n'est pas
// un artefact d'un zoom particulier.
export const FRACTION = 3 / 8;

/** Côté de la grille de tuiles couvrant la carte à ce zoom (z5 -> 12). */
export const gridFor = (z) => Math.round(FRACTION * 2 ** z);

/**
 * lat/lng Web Mercator -> [0,1] local carte. Les jeux de POI communautaires
 * (danharper, gta5-map) stockent leurs marqueurs en lat/lng parce qu'ils sont
 * bâtis sur Google Maps / Leaflet ; la projection Mercator est donc à défaire
 * ici, alors qu'elle ne l'est pas pour les coordonnées monde (voir plus bas).
 */
export function mercatorToNorm(lat, lng) {
  const rad = (lat * Math.PI) / 180;
  return {
    x: (lng + 180) / 360 / FRACTION,
    y: (1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2 / FRACTION,
  };
}

// Coordonnées monde du jeu -> [0,1]. La transformation est linéaire ET isotrope
// parce que la carte est une image plate simplement découpée en pyramide de
// tuiles, sans reprojection : une seule échelle suffit, d'où 3 paramètres.
//
// Aucune source ne publie ces constantes (les fils FiveM renvoient tous à
// « prends des points de référence et fais une régression »), donc recalage
// automatique : masque océan/route construit depuis l'image, puis maximisation
// des pixels bâti/route sous les 278 ATM + pompes à essence (objets toujours
// en zone construite, jamais en mer), océan compté en rejet dur. Optimum
// stable sur une plage de recherche large — pas un blocage sur borne — et
// 0/278 point en mer. Soit un carré d'environ 14 000 unités monde de côté.
export const WORLD_FIT = { S: 7.145e-5, X0: -5714, Y0: 8472 };

/** Coordonnées monde du jeu (X,Y) -> [0,1] local carte. Y inversé : le nord du
 *  jeu (Y croissant) est le haut de l'image (y décroissant). */
export function worldToNorm(X, Y) {
  const { S, X0, Y0 } = WORLD_FIT;
  return { x: (X - X0) * S, y: (Y0 - Y) * S };
}

export const inBounds = (p) => p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1;

/** Récupération avec retries — 144 tuiles à z5, un 503 isolé ne doit pas faire
 *  échouer tout l'import. */
export async function fetchRetry(url, { tries = 4, asBuffer = false } = {}) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return asBuffer ? Buffer.from(await r.arrayBuffer()) : await r.text();
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 250 * 2 ** i));
    }
  }
  throw new Error(`${url}: ${lastErr.message}`);
}

/** Exécute `jobs` avec au plus `limit` en vol — évite d'ouvrir 2 304 requêtes
 *  simultanées à z7. */
export async function pool(jobs, limit, onDone) {
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
