#!/usr/bin/env node
// Générateur de pyramide de tuiles — brique A3 du pipeline (docs/superpowers/
// plans/2026-07-20-data-pipeline-pseudocode.md). Rend un SVG carré en tuiles
// 256px pour le viewer CATiledLayer de l'app.
//   node tile.js [input.svg] [outDir] [maxZoom]
// Défauts : leonida-placeholder.svg → ./out, maxZoom 3.

import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import sharp from 'sharp';

const HERE = dirname(fileURLToPath(import.meta.url));
const TILE = 256;

const input = process.argv[2] ?? join(HERE, 'leonida-placeholder.svg');
const outDir = process.argv[3] ?? join(HERE, 'out');
const maxZoom = Number(process.argv[4] ?? 3);

let total = 0;
for (let z = 0; z <= maxZoom; z++) {
  const grid = 2 ** z;
  const size = TILE * grid;
  // Un seul rendu plein cadre par niveau, puis découpe — sharp re-rasterise le
  // SVG à la densité voulue, donc les traits restent nets à tous les zooms.
  const full = await sharp(input, { density: 72 * grid }).resize(size, size).png().toBuffer();
  for (let x = 0; x < grid; x++) {
    for (let y = 0; y < grid; y++) {
      const dir = join(outDir, String(z), String(x));
      mkdirSync(dir, { recursive: true });
      await sharp(full)
        .extract({ left: x * TILE, top: y * TILE, width: TILE, height: TILE })
        .png()
        .toFile(join(dir, `${y}.png`));
      total++;
    }
  }
  console.log(`z${z}: ${grid}×${grid} tiles`);
}

const manifest = {
  tileSize: TILE,
  maxZoom,
  tileCount: total,
  source: input.split('/').pop(),
  sourceSha256: createHash('sha256').update(await sharp(input).toBuffer()).digest('hex').slice(0, 16),
};
writeFileSync(join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(`${total} tiles + manifest.json → ${outDir}`);
