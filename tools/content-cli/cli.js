#!/usr/bin/env node
// Neon Compass admin CLI — brique C du pipeline (docs/superpowers/plans/
// 2026-07-20-data-pipeline-pseudocode.md). Commandes :
//   validate               valide content/{poi,poi-gtav,cheats,collections}/**.json
//   check-publishable      règles éditoriales (cheats: verifiedBy >= 2, marques déposées)
//   bundle                 régénère NeonCompass/Resources/POI/collections.json depuis
//                          content/collections (projection, jamais éditée à la main)
//   bundle --dry-run       équivalent de check-seeds (n'écrit rien)
//   check-seeds            vérifie que les socles embarqués (collections.json,
//                          seed-poi.json) ne sont pas en retard sur content/
//   release                LA commande à utiliser : arbre propre + validate +
//                          check-publishable + check-seeds, puis publish + bump.
//                          `release --dry-run` exécute les mêmes contrôles sans écrire.
//   translate --dry-run    liste les champs ES/IT/DE manquants (l'appel IA arrive avec Firebase)
//   publish --dry-run      montre le diff qui partirait vers Firestore
//   publish                pousse réellement vers Firestore (firebase-admin) et incrémente
//                          contentVersion dans Remote Config ; nécessite
//                          FIREBASE_SERVICE_ACCOUNT_PATH.
//   pull-drafts            matérialise les brouillons du mode éditeur (posés au doigt
//                          dans le build debug) en fichiers content/poi/*.json ;
//                          nécessite FIREBASE_SERVICE_ACCOUNT_PATH.
//   pull-drafts --file X   même chose depuis un fichier exporté par l'app (repli sans
//                          compte, cf. FileEditorDraftStore) ; aucun credential requis.
//   build-cdn              construit le site statique de contenu dans dist/ (JSON
//                          versionné, lisible sans SDK — voir cdn-build.mjs)
//   content-source [url|off]  affiche ou change la source de contenu lue par l'app
//                          (contentBaseURL dans Remote Config ; `off` = Firestore)
//   rules-diff             compare firestore.rules au ruleset actif en ligne
//   deploy-rules           affiche le diff PUIS déploie firestore.rules (racine du
//                          repo) comme ruleset actif sur le projet Firestore live ;
//                          nécessite FIREBASE_SERVICE_ACCOUNT_PATH.

import { execSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync, rmSync, mkdirSync, renameSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv/dist/2020.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CONTENT = join(ROOT, 'content');
const LANGS = ['fr', 'es', 'it', 'de'];
// Champs affichés dans l'UI : jamais de marque déposée (CLAUDE.md, spec §1).
const TRADEMARKS = /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/i;
const UI_FIELDS = ['title', 'note', 'effect'];
// Doit rester aligné sur BUNDLE_CHUNK_SIZE dans firestore-client.js et
// ContentBundle.chunkSize côté Swift — ici uniquement pour annoncer le nombre de
// fragments en dry-run.
const BUNDLE_CHUNK_SIZE = 500;

const ajv = new Ajv({ allErrors: true });
const compiled = {
  poi: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'poi.schema.json')))),
  cheats: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'cheat.schema.json')))),
  collections: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'collection.schema.json')))),
};

// Un « kind » est un répertoire de content/. Il porte son schéma et la
// collection Firestore visée.
//
// `poi-gtav` et `poi` partagent le schéma mais PAS la collection : les positions
// de la fixture sont normalisées sur la carte de référence, les afficher sur
// celle du jeu à venir poserait des centaines de pins à des endroits qui ne
// veulent rien dire. La séparation est délibérée côté app aussi
// (NeonCompass/Features/Map/MapModel.swift, `pois(for:)`).
const KINDS = {
  poi: { schema: 'poi', collection: 'poi' },
  'poi-gtav': { schema: 'poi', collection: 'poi_gtav' },
  cheats: { schema: 'cheats', collection: 'cheats' },
  collections: { schema: 'collections', collection: 'collections' },
};
const schemas = Object.fromEntries(
  Object.entries(KINDS).map(([kind, { schema }]) => [kind, compiled[schema]]),
);

function loadAll() {
  const entries = [];
  for (const kind of Object.keys(KINDS)) {
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
  console.log(`publish --dry-run: ${publishable.length} document(s) would be pushed`);
  if (!publishable.length) {
    console.log('  (nothing — all drafts)');
    return true;
  }
  // Résumé par collection, pas une ligne par document : à 539 entrées le détail
  // exhaustif noyait le seul chiffre qu'on lit vraiment, le nombre de fragments.
  for (const kind of Object.keys(KINDS)) {
    const docs = publishable.filter((e) => e.kind === kind);
    if (!docs.length) continue;
    const chunks = Math.ceil(docs.length / BUNDLE_CHUNK_SIZE);
    console.log(`  ${KINDS[kind].collection}: ${docs.length} doc(s) -> ${chunks} fragment(s)`);
  }
  return true;
}

const COLLECTIONS_SEED = join(ROOT, 'NeonCompass', 'Resources', 'POI', 'collections.json');
const POI_SEED = join(ROOT, 'NeonCompass', 'Resources', 'POI', 'seed-poi.json');

function collectionsSeedContent(entries) {
  const collections = entries
    .filter((e) => e.kind === 'collections')
    .map((e) => e.data)
    .sort((a, b) => a.id.localeCompare(b.id));
  return JSON.stringify(collections, null, 2) + '\n';
}

/** Régénère le catalogue de collections embarqué que l'app lit au démarrage.
 *  Même rôle que seed-poi.json côté carte : content/ reste la source de vérité,
 *  le bundle en est une projection — jamais une copie éditée à la main.
 *  Le filtre draft/published ne s'applique pas ici : il gouverne la publication
 *  Firestore, pas ce que le binaire embarque. */
function bundleCollections(entries) {
  const content = collectionsSeedContent(entries);
  writeFileSync(COLLECTIONS_SEED, content);
  console.log(`bundle: ${JSON.parse(content).length} collection(s) -> ${COLLECTIONS_SEED}`);
  return true;
}

/** Champs du POI que le socle embarqué porte réellement — les autres sont
 *  pipeline-only et absents du modèle Swift. */
function seedProjection(poi) {
  const { id, category, collection, position, title, note } = poi;
  return { id, category, collection, position, title, ...(note ? { note } : {}) };
}

/**
 * Vérifie que les deux fichiers embarqués sont à jour vis-à-vis de content/.
 *
 * C'est le garde-fou qui manquait : éditer un POI sans régénérer `seed-poi.json`
 * livre un binaire dont le socle est en retard sur le contenu publié, et rien ne
 * le signale — l'overlay masque l'écart au premier sync, mais pas au premier
 * lancement, ni hors ligne.
 *
 * Comparaison par identifiant et non par ordre : l'ordre d'émission du socle est
 * celui du pipeline, il n'a pas à être reproduit ici.
 */
function checkSeeds(entries) {
  let failures = 0;

  if (collectionsSeedContent(entries) !== readFileSync(COLLECTIONS_SEED, 'utf8')) {
    console.error(`FAIL ${COLLECTIONS_SEED} est en retard sur content/collections — lancer \`bundle\``);
    failures++;
  }

  const expected = new Map(
    entries
      .filter((e) => e.kind === 'poi-gtav')
      .map((e) => [e.data.id, JSON.stringify(seedProjection(e.data))]),
  );
  const actual = new Map(
    JSON.parse(readFileSync(POI_SEED, 'utf8')).map((p) => [p.id, JSON.stringify(seedProjection(p))]),
  );

  const missing = [...expected.keys()].filter((id) => !actual.has(id));
  const extra = [...actual.keys()].filter((id) => !expected.has(id));
  const drifted = [...expected.entries()].filter(([id, json]) => actual.has(id) && actual.get(id) !== json);

  for (const [label, ids] of [['absent(s) du socle', missing], ['en trop dans le socle', extra], ['divergent(s)', drifted.map(([id]) => id)]]) {
    if (!ids.length) continue;
    failures++;
    console.error(`FAIL ${ids.length} POI ${label} — relancer \`node tools/basemap/gtav-poi.mjs\``);
    ids.slice(0, 5).forEach((id) => console.error(`     ${id}`));
  }

  console.log(`check-seeds: ${failures === 0 ? 'socles à jour' : `${failures} écart(s)`}`);
  return failures === 0;
}

/** Refuse de publier depuis un arbre de travail sale : ce qui part vers
 *  Firestore doit correspondre à un commit, sinon on ne peut plus dire quelle
 *  version du contenu est en ligne. */
function requireCleanTree() {
  const dirty = execSync('git status --porcelain', { cwd: ROOT, encoding: 'utf8' }).trim();
  if (!dirty) return true;
  console.error('FAIL arbre de travail sale — committer avant de publier :');
  dirty.split('\n').slice(0, 10).forEach((l) => console.error(`     ${l}`));
  return false;
}

function currentCommit() {
  return execSync('git rev-parse --short HEAD', { cwd: ROOT, encoding: 'utf8' }).trim();
}

/**
 * Compare firestore.rules au ruleset actuellement actif sur le projet live.
 *
 * `deploy-rules` remplace le ruleset d'un bloc : une règle ajoutée directement en
 * console Firebase disparaîtrait sans laisser de trace. Regarder la cible avant
 * de l'écraser n'est pas une précaution de confort.
 *
 * Comparaison ligne à ligne, volontairement grossière : sur un fichier de règles
 * de cette taille, savoir QUELLES lignes diffèrent suffit — pas besoin d'un
 * algorithme de diff et de la dépendance qui va avec.
 */
async function rulesDiff() {
  const { fetchFirestoreRules } = await import('./firestore-client.js');
  const local = readFileSync(join(ROOT, 'firestore.rules'), 'utf8');
  const live = await fetchFirestoreRules();

  if (local.trim() === live.trim()) {
    console.log('rules-diff: le ruleset actif est identique à firestore.rules');
    return true;
  }

  const norm = (s) => s.split('\n').map((l) => l.trim()).filter(Boolean);
  const liveLines = norm(live);
  const localLines = norm(local);
  const onlyLive = liveLines.filter((l) => !localLines.includes(l));
  const onlyLocal = localLines.filter((l) => !liveLines.includes(l));

  console.log('rules-diff: le ruleset actif DIFFÈRE de firestore.rules');
  if (onlyLive.length) {
    console.log(`\n  présent en ligne, absent du dépôt (${onlyLive.length} ligne(s)) —`);
    console.log('  un déploiement les PERDRAIT :');
    onlyLive.forEach((l) => console.log(`  - ${l}`));
  }
  if (onlyLocal.length) {
    console.log(`\n  présent dans le dépôt, absent en ligne (${onlyLocal.length} ligne(s)) —`);
    console.log('  un déploiement les ajouterait :');
    onlyLocal.forEach((l) => console.log(`  + ${l}`));
  }
  return true;
}

/** Écriture réelle vers Firestore + bump de version. Partagée par `publish` et
 *  `release` : une seule implémentation, deux points d'entrée. */
async function publishAll(entries) {
  try {
    const publishable = entries.filter((e) => e.data.status === 'published');
    const { pushDocuments, pushBundles, incrementContentVersion } = await import('./firestore-client.js');
    const byKind = Object.fromEntries(Object.keys(KINDS).map((k) => [k, []]));
    publishable.forEach((e) => byKind[e.kind].push(e.data));

    for (const [kind, docs] of Object.entries(byKind)) {
      const { collection } = KINDS[kind];
      // Les documents unitaires restent : ils sont la surface d'écriture du mode
      // éditeur et ce qu'on inspecte dans la console. Mais l'app ne les lit plus
      // — à une lecture facturée par document, un bump de version coûtait autant
      // de lectures qu'il y a d'entrées, fois le nombre de clients. Elle lit les
      // agrégats.
      if (docs.length) await pushDocuments(collection, docs);
      const { chunks, pruned } = await pushBundles(collection, docs);
      console.log(`  ${collection}: ${docs.length} doc(s), ${chunks} fragment(s)${pruned ? `, ${pruned} périmé(s) supprimé(s)` : ''}`);
    }

    // Le SHA part avec la version : sans lui, « quelle version du contenu est en
    // ligne ? » n'a aucune réponse vérifiable.
    const commit = currentCommit();
    const newVersion = await incrementContentVersion(commit);
    console.log(`publish: ${publishable.length} document(s), contentVersion → ${newVersion} (${commit})`);
    return true;
  } catch (err) {
    console.error(err.message);
    return false;
  }
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
  case 'bundle':
    ok = validate(entries) && (dry ? checkSeeds(entries) : bundleCollections(entries));
    break;
  case 'check-seeds':
    ok = checkSeeds(entries);
    break;
  case 'translate':
    if (!dry) { console.error('translate: only --dry-run is implemented until Firebase is provisioned'); ok = false; break; }
    ok = translateDryRun(entries);
    break;
  case 'publish':
    if (dry) { ok = validate(entries) && checkPublishable(entries) && publishDryRun(entries); break; }
    if (!(validate(entries) && checkPublishable(entries))) { ok = false; break; }
    ok = await publishAll(entries);
    break;
  // Un seul point d'entrée pour toute la chaîne : valider, vérifier les règles
  // éditoriales, s'assurer que les socles embarqués ne sont pas en retard sur
  // content/, puis publier et bumper la version. Chaîner ces commandes à la main
  // est exactement le genre de séquence dont on oublie une étape.
  case 'release': {
    const gates = [
      ['validate', () => validate(entries)],
      ['check-publishable', () => checkPublishable(entries)],
      ['check-seeds', () => checkSeeds(entries)],
    ];
    // L'arbre propre n'est exigé qu'en publication réelle : un --dry-run doit
    // rester utilisable en pleine édition.
    if (!dry) gates.unshift(['clean-tree', requireCleanTree]);

    ok = true;
    for (const [name, run] of gates) {
      if (run()) continue;
      console.error(`release: arrêté à l'étape « ${name} »`);
      ok = false;
      break;
    }
    if (!ok) break;

    if (dry) {
      ok = publishDryRun(entries);
      console.log('release --dry-run: aucune écriture, aucun bump de version');
      break;
    }
    ok = await publishAll(entries);
    break;
  }
  case 'rules-diff':
    try {
      ok = await rulesDiff();
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'deploy-rules':
    try {
      // La cible s'affiche avant d'être écrasée, systématiquement : c'est le
      // seul moment où une divergence introduite en console est encore visible.
      await rulesDiff();
      console.log('');
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
  case 'content-source':
    try {
      const { getRemoteConfigParameter, setRemoteConfigParameter } = await import('./firestore-client.js');
      const [target] = flags;
      if (!target) {
        const current = await getRemoteConfigParameter('contentBaseURL');
        console.log(current ? `content-source: CDN — ${current}` : 'content-source: Firestore (contentBaseURL vide)');
        ok = true;
        break;
      }
      // `off` efface la valeur plutôt que de la supprimer : le paramètre reste
      // visible en console, ce qui rend le repli explicite au lieu d'être une
      // absence qu'on interprète.
      const value = target === 'off' ? '' : target;
      if (value && !/^https:\/\/[^\s]+$/.test(value)) throw new Error(`URL refusée : ${target}`);
      await setRemoteConfigParameter(
        'contentBaseURL',
        value,
        "Base du contenu statique servi par CDN. Vide = l'app lit Firestore (repli sans mise à jour)."
      );
      console.log(value ? `content-source: les clients liront ${value}` : 'content-source: repli sur Firestore');
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'build-cdn': {
    // La version vient du nombre de commits : monotone, déterministe, et
    // calculable hors ligne — contrairement à `contentVersion` de Remote Config,
    // qui exige des credentials. La construction doit tourner en CI sans secret.
    const version = Number(execSync('git rev-list --count HEAD', { cwd: ROOT, encoding: 'utf8' }).trim());
    const commit = execSync('git rev-parse --short HEAD', { cwd: ROOT, encoding: 'utf8' }).trim();
    const { buildSite } = await import('./cdn-build.mjs');
    const files = buildSite(entries, KINDS, { version, commit });

    const dist = join(ROOT, 'tools', 'content-cli', 'dist');
    rmSync(dist, { recursive: true, force: true });
    for (const file of files) {
      const target = join(dist, file.path);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, `${JSON.stringify(file.json)}\n`);
    }

    const published = entries.filter((e) => e.data.status === 'published').length;
    console.log(`build-cdn: v${version} (${commit}) — ${published} entrée(s) publiée(s), ${files.length} fichier(s) dans dist/`);
    console.log('  déploiement : firebase deploy --only hosting');
    ok = true;
    break;
  }
  case 'pull-drafts':
    try {
      const { materialize } = await import('./draft-to-poi.mjs');

      // Deux sources, un seul traitement. Le fichier est le repli quand aucun
      // compte n'existe (cf. FileEditorDraftStore côté app) : il ne demande
      // aucun credential, donc il fonctionne même sans adhésion au programme
      // développeur Apple.
      const fileIndex = flags.indexOf('--file');
      const draftFile = fileIndex >= 0 ? flags[fileIndex + 1] : null;
      if (fileIndex >= 0 && !draftFile) throw new Error('usage: cli.js pull-drafts --file <chemin>');

      let drafts;
      let markApplied;
      if (draftFile) {
        drafts = JSON.parse(readFileSync(draftFile, 'utf8'));
        if (!Array.isArray(drafts)) throw new Error(`${draftFile} ne contient pas un tableau de brouillons`);
        // Le fichier est renommé plutôt que supprimé : une capture de terrain ne
        // se refait pas, et l'idempotence par processedFrom rend un rejeu
        // inoffensif de toute façon.
        markApplied = async () => {
          const archived = draftFile.replace(/\.json$/, '') + '.applied.json';
          renameSync(draftFile, archived);
          console.log(`  archivé ${archived}`);
        };
      } else {
        const { listEditorDrafts, markEditorDraftsApplied } = await import('./firestore-client.js');
        drafts = await listEditorDrafts();
        markApplied = (ids) => markEditorDraftsApplied(ids);
      }

      if (!drafts.length) {
        console.log('pull-drafts: aucun brouillon en attente');
        ok = true;
        break;
      }

      const dir = join(CONTENT, 'poi');
      const existing = readdirSync(dir)
        .filter((name) => name.endsWith('.json'))
        .map((name) => ({
          path: join('content', 'poi', name),
          data: JSON.parse(readFileSync(join(dir, name), 'utf8')),
        }));

      const capturedOn = new Date().toISOString().slice(0, 10);
      const result = materialize(drafts, existing, { capturedOn });

      // Un lot en conflit n'est jamais appliqué à moitié : on signale et on sort.
      if (result.conflicts.length) {
        result.conflicts.forEach((c) => console.error(`  conflit ${c.id}: ${c.reason}`));
        console.error("pull-drafts: rien appliqué — résoudre les conflits d'abord");
        ok = false;
        break;
      }

      result.writes.forEach(({ path, data }) => {
        writeFileSync(join(ROOT, path), `${JSON.stringify(data, null, 2)}\n`);
        console.log(`  écrit  ${path}`);
      });
      result.deletes.forEach((path) => {
        rmSync(join(ROOT, path));
        console.log(`  retiré ${path}`);
      });
      result.skipped.forEach((s) => console.log(`  ignoré ${s.id}: ${s.reason}`));

      await markApplied(result.applied);
      console.log(`pull-drafts: ${result.applied.length} brouillon(s) appliqué(s) — relire puis committer`);
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
    console.error('usage: cli.js <validate|check-publishable|translate --dry-run|publish --dry-run|deploy-rules|build-cdn|content-source [url|off]|pull-drafts [--file X]|moderate:list|moderate:approve <id>|moderate:reject <id>|shadow-ban <uid>|lift-shadow-ban <uid>|kill-switch [on|off]>');
    ok = false;
}

process.exit(ok ? 0 : 1);
