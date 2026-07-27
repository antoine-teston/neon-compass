#!/usr/bin/env node
// Neon Compass admin CLI — brique C du pipeline (docs/superpowers/plans/
// 2026-07-20-data-pipeline-pseudocode.md). Commandes :
//   validate               valide content/{poi,cheats,collections}/**.json contre les schémas
//   check-publishable      règles éditoriales (cheats: verifiedBy >= 2, marques déposées)
//   translate --dry-run    liste les champs ES/IT/DE manquants (l'appel IA arrive avec Firebase)
//   publish --dry-run      montre le diff qui partirait vers Firestore
//   publish                pousse réellement vers Firestore (firebase-admin) et incrémente
//                          contentVersion dans Remote Config ; nécessite
//                          FIREBASE_SERVICE_ACCOUNT_PATH.
//   deploy-rules           déploie firestore.rules (racine du repo) comme ruleset actif
//                          sur le projet Firestore live ; nécessite
//                          FIREBASE_SERVICE_ACCOUNT_PATH.

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
  collections: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'collection.schema.json')))),
};
const KINDS = Object.keys(schemas);

function loadAll() {
  const entries = [];
  for (const kind of KINDS) {
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

let ok;

switch (cmd) {
  case 'validate':
    ok = validate(entries);
    break;
  case 'check-publishable':
    ok = checkPublishable(entries);
    break;
  case 'translate':
    if (!dry) { console.error('translate: only --dry-run is implemented until Firebase is provisioned'); ok = false; break; }
    ok = translateDryRun(entries);
    break;
  case 'publish':
    if (dry) { ok = validate(entries) && checkPublishable(entries) && publishDryRun(entries); break; }
    if (!(validate(entries) && checkPublishable(entries))) { ok = false; break; }
    try {
      const publishable = entries.filter((e) => e.data.status === 'published');
      const { pushDocuments, incrementContentVersion } = await import('./firestore-client.js');
      const byKind = Object.fromEntries(KINDS.map((k) => [k, []]));
      publishable.forEach((e) => byKind[e.kind].push(e.data));
      for (const [kind, docs] of Object.entries(byKind)) {
        if (docs.length) await pushDocuments(kind, docs);
      }
      const newVersion = await incrementContentVersion();
      console.log(`publish: pushed ${publishable.length} document(s), contentVersion → ${newVersion}`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'deploy-rules':
    try {
      const rulesSource = readFileSync(join(ROOT, 'firestore.rules'), 'utf8');
      const { deployFirestoreRules } = await import('./firestore-client.js');
      await deployFirestoreRules(rulesSource);
      console.log('deploy-rules: firestore.rules released as the active Firestore ruleset');
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'moderate:list':
    try {
      const { listPendingContributions } = await import('./firestore-client.js');
      const pending = await listPendingContributions();
      if (!pending.length) {
        console.log('moderate:list: nothing pending');
      } else {
        pending.forEach((c) => {
          const flag = c.flaggedForReview ? ' [FLAGGED]' : '';
          console.log(`${c.id}${flag} — [${c.category}] "${c.title}" by ${c.authorHandle}`);
        });
      }
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'moderate:approve':
    try {
      const [id] = flags;
      if (!id) throw new Error('usage: cli.js moderate:approve <contributionId>');
      const { approveContribution } = await import('./firestore-client.js');
      await approveContribution(id);
      console.log(`moderate:approve: ${id} approved`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'moderate:reject':
    try {
      const [id] = flags;
      if (!id) throw new Error('usage: cli.js moderate:reject <contributionId>');
      const { rejectContribution } = await import('./firestore-client.js');
      await rejectContribution(id);
      console.log(`moderate:reject: ${id} rejected`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'shadow-ban':
    try {
      const [uid] = flags;
      if (!uid) throw new Error('usage: cli.js shadow-ban <uid>');
      const { shadowBanUser } = await import('./firestore-client.js');
      await shadowBanUser(uid);
      console.log(`shadow-ban: ${uid} shadow-banned, existing approved spots hidden`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'lift-shadow-ban':
    try {
      const [uid] = flags;
      if (!uid) throw new Error('usage: cli.js lift-shadow-ban <uid>');
      const { liftShadowBan } = await import('./firestore-client.js');
      await liftShadowBan(uid);
      console.log(`lift-shadow-ban: ${uid} restored, existing spots visible again`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'kill-switch':
    try {
      const [state] = flags.filter((f) => f !== '--dry-run');
      const { getCommunityContributionsEnabled, setCommunityContributionsEnabled } = await import('./firestore-client.js');
      if (!state) {
        const enabled = await getCommunityContributionsEnabled();
        console.log(`kill-switch: community contributions currently ${enabled ? 'ENABLED' : 'DISABLED'}`);
      } else if (state === 'on' || state === 'off') {
        await setCommunityContributionsEnabled(state === 'on');
        console.log(`kill-switch: community contributions now ${state === 'on' ? 'ENABLED' : 'DISABLED'}`);
      } else {
        throw new Error("usage: cli.js kill-switch [on|off]  (no argument = show current state)");
      }
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  default:
    console.error('usage: cli.js <validate|check-publishable|translate --dry-run|publish --dry-run|deploy-rules|moderate:list|moderate:approve <id>|moderate:reject <id>|shadow-ban <uid>|lift-shadow-ban <uid>|kill-switch [on|off]>');
    ok = false;
}

process.exit(ok ? 0 : 1);
