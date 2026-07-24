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
// sharp re-rasterise le SVG à la densité voulue, donc les traits restent
// nets à la résolution cible — même technique que l'ancienne pyramide de
// tuiles pour son niveau de zoom le plus détaillé.
const density = 72 * (size / 256);
const image = await sharp(input, { density }).resize(size, size).png().toBuffer();
await sharp(image).toFile(join(outDir, 'island.png'));

const manifest = {
  size,
  source: input.split('/').pop(),
  sourceSha256: createHash('sha256').update(await sharp(input).toBuffer()).digest('hex').slice(0, 16),
};
writeFileSync(join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(`island.png (${size}×${size}) + manifest.json → ${outDir}`);
