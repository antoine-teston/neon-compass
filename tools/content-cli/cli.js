#!/usr/bin/env node
// Neon Compass admin CLI — brique C du pipeline (docs/superpowers/plans/
// 2026-07-20-data-pipeline-pseudocode.md). Commandes :
//   validate               valide content/{poi,cheats}/**.json contre les schémas
//   check-publishable      règles éditoriales (cheats: verifiedBy >= 2, marques déposées)
//   translate --dry-run    liste les champs ES/IT/DE manquants (l'appel IA arrive avec Firebase)
//   publish --dry-run      montre le diff qui partirait vers Firestore
// Firestore n'étant pas encore provisionné, publish sans --dry-run refuse de tourner.

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv/dist/2020.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CONTENT = join(ROOT, 'content');
const LANGS = ['fr', 'es', 'it', 'de'];
// Champs affichés dans l'UI : jamais de marque déposée (CLAUDE.md, spec §1).
const TRADEMARKS = /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/i;
const UI_FIELDS = ['title', 'note', 'effect'];

const ajv = new Ajv({ allErrors: true });
const schemas = {
  poi: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'poi.schema.json')))),
  cheats: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'cheat.schema.json')))),
};

function loadAll() {
  const entries = [];
  for (const kind of ['poi', 'cheats']) {
    const dir = join(CONTENT, kind);
    for (const f of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
      entries.push({ kind, file: `${kind}/${f}`, data: JSON.parse(readFileSync(join(dir, f))) });
    }
  }
  return entries;
}

function validate(entries) {
  let failures = 0;
  for (const { kind, file, data } of entries) {
    if (!schemas[kind](data)) {
      failures++;
      console.error(`FAIL ${file}`);
      for (const e of schemas[kind].errors) console.error(`     ${e.instancePath || '/'} ${e.message}`);
    }
  }
  console.log(`validate: ${entries.length - failures}/${entries.length} OK`);
  return failures === 0;
}

function checkPublishable(entries) {
  let failures = 0;
  for (const { kind, file, data } of entries) {
    const problems = [];
    if (kind === 'cheats' && data.status === 'published' && (data.verifiedBy?.length ?? 0) < 2) {
      problems.push('published cheat requires verifiedBy >= 2 sources');
    }
    for (const field of UI_FIELDS) {
      for (const [lang, text] of Object.entries(data[field] ?? {})) {
        const m = text.match(TRADEMARKS);
        if (m) problems.push(`trademark "${m[0]}" in ${field}.${lang}`);
      }
    }
    if (problems.length) {
      failures++;
      console.error(`FAIL ${file}`);
      problems.forEach((p) => console.error(`     ${p}`));
    }
  }
  console.log(`check-publishable: ${entries.length - failures}/${entries.length} OK`);
  return failures === 0;
}

function translateDryRun(entries) {
  let missing = 0;
  for (const { file, data } of entries) {
    for (const field of UI_FIELDS) {
      if (!data[field]) continue;
      const absent = LANGS.filter((l) => !data[field][l]);
      if (absent.length) {
        missing += absent.length;
        console.log(`${file} ${field}: missing ${absent.join(', ')}`);
      }
    }
  }
  console.log(`translate --dry-run: ${missing} field(s) would be AI-translated`);
  return true;
}

function publishDryRun(entries) {
  const publishable = entries.filter((e) => e.data.status === 'published');
  console.log(`publish --dry-run: ${publishable.length} document(s) would be pushed:`);
  publishable.forEach((e) => console.log(`  ${e.kind}/${e.data.id}`));
  if (!publishable.length) console.log('  (nothing — all drafts)');
  return true;
}

const [cmd, ...flags] = process.argv.slice(2);
const dry = flags.includes('--dry-run');
const entries = loadAll();

const ok = (() => {
  switch (cmd) {
    case 'validate':
      return validate(entries);
    case 'check-publishable':
      return checkPublishable(entries);
    case 'translate':
      if (!dry) { console.error('translate: only --dry-run is implemented until Firebase is provisioned'); return false; }
      return translateDryRun(entries);
    case 'publish':
      if (!dry) { console.error('publish: refusing — Firestore is not provisioned yet. Use --dry-run.'); return false; }
      return validate(entries) && checkPublishable(entries) && publishDryRun(entries);
    default:
      console.error('usage: cli.js <validate|check-publishable|translate --dry-run|publish --dry-run>');
      return false;
  }
})();

process.exit(ok ? 0 : 1);
