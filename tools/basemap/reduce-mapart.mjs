// Étage réduit des cartes de Leonida : 8 192 px → 4 096 px, une fois pour
// toutes, à la construction.
//
// POURQUOI un fichier et non un sous-échantillonnage à l'exécution. ImageIO ne
// sait pas décoder un PNG partiellement : `kCGImageSourceThumbnailMaxPixelSize`
// inflate les 8 192 px puis rééchantillonne, et `kCGImageSourceSubsampleFactor`
// est ignoré pour ce format. Mesuré sur island-vi.png, deux tours par chemin :
//
//   décodage natif        8192×8192    69–189 ms
//   vignette 4 096 px     4096×4096   779–890 ms
//   subsampleFactor 2     8192×8192    68 ms  (facteur ignoré)
//
// Soit dix fois le prix du décodage entier POUR obtenir moins de pixels, sans
// même éviter le pic de 256 Mio puisque l'image entière est inflatée en chemin.
// Réduire ici coûte deux fichiers dans le paquet et rend l'étage réduit
// réellement moins cher — c'est tout l'intérêt qu'il était censé avoir.
//
// Dérivé des PNG de 8 192 px DÉJÀ dans le dépôt, et non d'un second passage du
// pipeline : un seul saut de provenance, et les deux étages ne peuvent pas
// diverger par dérive du classificateur. Le cadrage est donc identique par
// construction, ce que `MapArtResourcesTests` vérifie.
//
//   node tools/basemap/reduce-mapart.mjs
//
// À relancer après toute régénération de island-vi.png / island-vi-classic.png.

import sharp from 'sharp';
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ART = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'NeonCompass', 'Resources', 'MapArt');

// Doit rester égal à `MapArtDetail.overviewMaxPixels`. Un test le vérifie côté
// Swift, sur les octets du fichier — c'est lui qui fait autorité, pas ce commentaire.
const REDUCED = 4096;

// `colors: 256` et `effort: 9` : les mêmes réglages que l'encodage d'origine
// dans gtavi-map.mjs. Le rehaussement suit la réduction pour la même raison
// qu'il suit le resize là-bas — lanczos3 adoucit, et la carte est faite de
// traits fins (routes, libellés).
for (const name of ['island-vi', 'island-vi-classic']) {
  const source = join(ART, `${name}.png`);
  const target = join(ART, `${name}-reduced.png`);
  const { width, height } = await sharp(source).metadata();
  if (width !== height) throw new Error(`${name}.png n'est pas carrée (${width}×${height})`);
  if (width <= REDUCED) throw new Error(`${name}.png fait déjà ${width} px : pas d'étage réduit à produire`);

  const buffer = await sharp(source)
    .resize(REDUCED, REDUCED, { kernel: 'lanczos3' })
    .sharpen({ sigma: 1, m1: 0.6, m2: 2 })
    .png({ palette: true, colors: 256, effort: 9 })
    .toBuffer();
  writeFileSync(target, buffer);
  const before = readFileSync(source).length;
  console.log(
    `  ${name}-reduced.png  ${width}→${REDUCED} px  ` +
      `${(buffer.length / 1024).toFixed(0)} Ko (source ${(before / 1024).toFixed(0)} Ko)`
  );
}
