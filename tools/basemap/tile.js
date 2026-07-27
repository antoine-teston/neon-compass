#!/usr/bin/env node
// Générateur d'image de carte — brique A3 du pipeline (docs/superpowers/
// plans/2026-07-20-data-pipeline-pseudocode.md). Rend un SVG carré en une
// image plate unique — la pyramide de tuiles CATiledLayer a été retirée
// (docs/superpowers/plans/2026-07-24-plan-map-engine-rebuild.md) : la carte
// est une image unique bornée (~500 Ko), pas un document gigapixel, donc pas
// besoin de streaming par tuiles.
//   node tile.js [input.svg] [outDir] [size]
// Défauts : island-placeholder.svg → ./out, size 2048.

import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import sharp from 'sharp';

const HERE = dirname(fileURLToPath(import.meta.url));

const input = process.argv[2] ?? join(HERE, 'island-placeholder.svg');
const outDir = process.argv[3] ?? join(HERE, 'out');
const size = Number(process.argv[4] ?? 2048);

mkdirSync(outDir, { recursive: true });
// sharp re-rasterise le SVG à la densité voulue, donc les traits restent nets
// à la résolution cible. La densité se calcule sur la taille INTRINSÈQUE du
// SVG, pas sur un pas de tuile : l'ancienne formule (72 × size/256) héritait
// de la pyramide de tuiles et rasterisait un SVG de 1 024 px à 16 384 px dès
// qu'on demandait 4 096 — au-delà de la limite de pixels de sharp, donc échec.
const intrinsic = (await sharp(input).metadata()).width || size;
const density = Math.round(72 * (size / intrinsic));
const image = await sharp(input, { density }).resize(size, size).png().toBuffer();
await sharp(image).toFile(join(outDir, 'island.png'));

const manifest = {
  size,
  source: input.split('/').pop(),
  sourceSha256: createHash('sha256').update(await sharp(input).toBuffer()).digest('hex').slice(0, 16),
};
writeFileSync(join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(`island.png (${size}×${size}) + manifest.json → ${outDir}`);
