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
//   translate --dry-run    liste les champs ES/IT/DE manquants
//   publish --dry-run      montre ce qui partirait vers le CDN
//   publish                construit le site statique et le téléverse sur Storage ;
//                          nécessite SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY.
//   pull-drafts            matérialise les brouillons du mode éditeur (posés au doigt
//                          dans le build debug) en fichiers content/poi/*.json ;
//                          nécessite SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY.
//   pull-drafts --file X   même chose depuis un fichier exporté par l'app (repli sans
//                          compte, cf. FileEditorDraftStore) ; aucun credential requis.
//   pull-news              matérialise les faits `kind: "news"` de content/inbox en
//                          squelettes content/news/*.json à rédiger ; idempotent
//                          (cf. facts-to-news.mjs), aucun credential requis.
//   pull-news --dry-run    montre ce qui serait matérialisé sans rien écrire.
//   pull-online-events     matérialise les faits `kind: "online-event"` de content/inbox
//                          en squelettes content/online-events/*.json à rédiger ;
//                          idempotent (cf. facts-to-online-event.mjs), aucun
//                          credential requis.
//   pull-online-events --dry-run  montre ce qui serait matérialisé sans rien écrire.
//   build-cdn              construit le site statique de contenu dans dist/ (JSON
//                          versionné, lisible sans SDK — voir cdn-build.mjs)
//   deploy-cdn             téléverse dist/ dans le bucket public `cdn`
//   content-source [url|off]  affiche ou change la source de contenu lue par l'app
//                          (contentBaseURL dans app_config ; `off` = socle embarqué seul)
//
// Les règles d'accès n'ont plus de commande : ce sont des politiques RLS
// versionnées dans supabase/migrations/, déployées par `supabase db push` et
// relues en pull request — pas un fichier poussé par une API.

import { execSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync, rmSync, mkdirSync, renameSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { deflateRawSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv/dist/2020.js';
import {
  notANominativeName,
  nominativeFieldsFor,
  nominativeListFieldsFor,
  redactedListFieldsFor,
} from './nominative-fields.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CONTENT = join(ROOT, 'content');
const LANGS = ['fr', 'es', 'it', 'de'];
// Champs affichés dans l'UI : jamais de marque déposée (CLAUDE.md, spec §1).
const TRADEMARKS = /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/i;
const UI_FIELDS = ['title', 'note', 'effect', 'body'];
// Doit rester aligné sur CHUNK_SIZE dans cdn-build.mjs et ContentBundle.chunkSize
// côté Swift — ici uniquement pour annoncer le nombre de fragments en dry-run.
const BUNDLE_CHUNK_SIZE = 500;

const ajv = new Ajv({ allErrors: true });
const compiled = {
  poi: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'poi.schema.json')))),
  cheats: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'cheat.schema.json')))),
  collections: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'collection.schema.json')))),
  news: ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'news.schema.json')))),
  'online-events': ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'online-event.schema.json')))),
};

// Un « kind » est un répertoire de content/. Il porte son schéma et le nom de
// collection publié sur le CDN.
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
  news: { schema: 'news', collection: 'news' },
  'online-events': { schema: 'online-events', collection: 'online_events' },
};
const schemas = Object.fromEntries(
  Object.entries(KINDS).map(([kind, { schema }]) => [kind, compiled[schema]]),
);

function loadAll() {
  const entries = [];
  for (const kind of Object.keys(KINDS)) {
    const dir = join(CONTENT, kind);
    // Un kind dont le répertoire n'existe pas encore n'est pas une erreur : il
    // est simplement vide. Sans ce garde-fou, déclarer un kind avant sa première
    // matérialisation ferait échouer TOUTES les commandes, `pull-news` comprise
    // — c'est-à-dire précisément celle qui crée le répertoire.
    if (!existsSync(dir)) continue;
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
    // Un squelette de `pull-news` porte encore son texte d'attente. Publier
    // « À rédiger » dans le fil est un accident que seule une machine peut
    // attraper de façon fiable — c'est exactement ce qui arriverait à un run
    // hebdomadaire dont l'étape de rédaction a échoué en silence.
    if ((kind === 'news' || kind === 'online-events') && data.status === 'published' && data.needsRewrite) {
      problems.push('published news item is still an unwritten skeleton (needsRewrite)');
    }
    // Une rumeur ne part pas dans le fil. L'app est un compagnon non officiel :
    // sa crédibilité tient à ne jamais présenter une spéculation de presse comme
    // une actualité. Une rumeur peut vivre en `draft` (elle garde sa trace et
    // son id), elle ne franchit pas la publication. Assouplir cette règle est
    // une décision éditoriale, pas un détail de pipeline.
    if ((kind === 'news' || kind === 'online-events') && data.status === 'published' && data.confidence === 'rumor') {
      problems.push('published entry cannot rest on a rumor (confidence: rumor)');
    }
    for (const field of UI_FIELDS) {
      for (const [lang, text] of Object.entries(data[field] ?? {})) {
        const m = text.match(TRADEMARKS);
        if (m) problems.push(`trademark "${m[0]}" in ${field}.${lang}`);
      }
    }
    // Une carte affiche aussi des textes que `UI_FIELDS` ne voit pas — ceux que
    // portent les listes. Ils ne rejoignent pas `UI_FIELDS` pour autant : celui-ci
    // sert aussi à `translate`, qui réclamerait alors une traduction pour des
    // noms propres.
    //
    // Deux régimes, et la frontière est celle de l'usage référentiel :
    //
    //  - un texte RÉDIGÉ par nous (`bonuses[].label`) n'a aucune raison de porter
    //    une marque. Il est scanné comme `title`.
    //  - un champ NOMINATIF ne fait que nommer le produit d'un tiers pour en
    //    parler. C'est l'usage que la presse spécialisée fait tous les jours, et
    //    la contrainte IP du projet (CLAUDE.md) porte sur l'IDENTITÉ de l'app —
    //    nom, icône, sous-titre App Store, bundle ID — pas sur le contenu.
    //    L'exception n'est PAS gratuite : ces champs doivent prouver qu'ils sont
    //    bien des noms, et c'est vérifié ICI même. Déléguer cette vérification à
    //    `check-originality` aurait laissé les deux contrôles se renvoyer la
    //    responsabilité d'une permission qu'aucun des deux n'aurait justifiée.
    for (const [listField, textField] of redactedListFieldsFor(kind)) {
      (data[listField] ?? []).forEach((item, index) => {
        for (const [lang, text] of Object.entries(item?.[textField] ?? {})) {
          const m = text.match(TRADEMARKS);
          if (m) problems.push(`trademark "${m[0]}" in ${listField}[${index}].${textField}.${lang}`);
        }
      });
    }
    for (const field of nominativeFieldsFor(kind)) {
      for (const [lang, text] of Object.entries(data[field] ?? {})) {
        const problem = notANominativeName(text);
        if (problem) problems.push(`${field}.${lang} n'est pas un nom — ${problem}`);
      }
    }
    for (const [listField, textField] of nominativeListFieldsFor(kind)) {
      (data[listField] ?? []).forEach((item, index) => {
        for (const [lang, text] of Object.entries(item?.[textField] ?? {})) {
          const problem = notANominativeName(text);
          if (problem) problems.push(`${listField}[${index}].${textField}.${lang} n'est pas un nom — ${problem}`);
        }
      });
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
const CHEATS_SEED = join(ROOT, 'NeonCompass', 'Resources', 'Cheats', 'seed-cheats.json');

function collectionsSeedContent(entries) {
  const collections = entries
    .filter((e) => e.kind === 'collections')
    .map((e) => e.data)
    .sort((a, b) => a.id.localeCompare(b.id));
  return JSON.stringify(collections, null, 2) + '\n';
}

/** Un socle absent est un écart à signaler, pas une exception à faire remonter :
 *  sur une copie fraîche du dépôt, `check-seeds` doit dire quoi lancer, pas
 *  échouer sur un ENOENT. */
function safeRead(path) {
  try {
    return readFileSync(path, 'utf8');
  } catch {
    return null;
  }
}

/** Champs du cheat que le socle embarqué porte réellement — les autres sont
 *  pipeline-only et absents du modèle Swift. */
function cheatSeedProjection(cheat) {
  const { id, game, category, effect, codes, blocksTrophies } = cheat;
  return { id, game, category, effect, codes, blocksTrophies };
}

/** Socle des codes. Ils existent parce qu'un écran de codes qui attend le réseau
 *  ne sert à rien manette en main, et parce que les codes d'un jeu terminé ne
 *  changent plus.
 *
 *  Tri par identifiant : l'ordre du socle ne doit pas dépendre de l'ordre de
 *  lecture du disque, sinon `check-seeds` signale une dérive d'une machine à
 *  l'autre. Le kind est `cheats` — un kind est un répertoire de content/, pas un
 *  nom de schéma (celui-ci s'appelle cheat.schema.json). */
function cheatsSeedContent(entries) {
  const cheats = entries
    .filter((e) => e.kind === 'cheats')
    .map((e) => cheatSeedProjection(e.data))
    .sort((a, b) => a.id.localeCompare(b.id));
  return JSON.stringify(cheats, null, 2) + '\n';
}

/** Régénère les socles embarqués que l'app lit au démarrage.
 *  Même rôle que seed-poi.json côté carte : content/ reste la source de vérité,
 *  le bundle en est une projection — jamais une copie éditée à la main.
 *  Le filtre draft/published ne s'applique pas ici : il gouverne la publication
 *  le CDN, pas ce que le binaire embarque. */
function bundleCollections(entries) {
  const cheats = cheatsSeedContent(entries);
  writeFileSync(CHEATS_SEED, cheats);
  console.log(`bundle: ${JSON.parse(cheats).length} cheat(s) -> ${CHEATS_SEED}`);
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

  // Sans cette garde, éditer un code sans régénérer le socle livre un binaire
  // dont les codes sont en retard sur le contenu, et rien ne le signale : le
  // premier sync masque l'écart, pas le premier lancement ni le hors-ligne.
  if (cheatsSeedContent(entries) !== safeRead(CHEATS_SEED)) {
    console.error(`FAIL ${CHEATS_SEED} est en retard sur content/cheats — lancer \`bundle\``);
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
 *  le CDN doit correspondre à un commit, sinon on ne peut plus dire quelle
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


/** Publication réelle : construction du site statique puis téléversement sur
 *  Storage. Partagée par `publish` et `release` — une seule implémentation, deux
 *  points d'entrée.
 *
 *  Il n'y a plus d'écriture en base : le CDN est la seule source de contenu, et
 *  la version de chaque collection vit dans le manifeste. */
async function publishAll() {
  try {
    const { execFileSync } = await import('node:child_process');
    const here = dirname(fileURLToPath(import.meta.url));
    execFileSync(process.execPath, [join(here, 'cli.js'), 'build-cdn'], { stdio: 'inherit' });
    const { uploadSite } = await import('./supabase-client.js');
    const count = await uploadSite(join(ROOT, 'tools', 'content-cli', 'dist'));
    console.log(`publish: ${count} objet(s) téléversé(s) dans le bucket cdn`);
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
    if (!dry) { console.error('translate: seul --dry-run est implémenté (l\'appel IA reste à câbler)'); ok = false; break; }
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
  case 'content-source':
    try {
      const { getConfig, setConfig } = await import('./supabase-client.js');
      const [target] = flags;
      if (!target) {
        const current = await getConfig('contentBaseURL');
        console.log(current ? `content-source: ${current}` : 'content-source: aucune (socle embarqué seul)');
        ok = true;
        break;
      }
      // `off` efface la valeur plutôt que de supprimer la ligne : le paramètre
      // reste visible dans l'éditeur de table, ce qui rend l'extinction
      // explicite au lieu d'être une absence qu'on interprète.
      //
      // C'est la porte de sortie de la décision d'héberger le contenu sur
      // Storage : changer d'hébergeur ne demande aucune mise à jour de l'app.
      const value = target === 'off' ? '' : target;
      if (value && !/^https:\/\/[^\s]+$/.test(value)) throw new Error(`URL refusée : ${target}`);
      await setConfig('contentBaseURL', value);
      console.log(value ? `content-source: les clients liront ${value}` : 'content-source: source éteinte');
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'build-cdn': {
    // La version vient du nombre de commits : monotone, déterministe, et
    // calculable hors ligne. La construction doit tourner en CI sans secret.
    const version = Number(execSync('git rev-list --count HEAD', { cwd: ROOT, encoding: 'utf8' }).trim());
    const commit = execSync('git rev-parse --short HEAD', { cwd: ROOT, encoding: 'utf8' }).trim();
    const { buildSite } = await import('./cdn-build.mjs');

    // Le verrou porte la version ET l'empreinte de chaque collection à la
    // dernière publication. C'est lui qui permet à une collection inchangée de
    // garder son chemin, donc son cache. Versionné dans le dépôt plutôt que relu
    // depuis le CDN : déterministe, hors ligne, et le diff se relit en PR.
    const lockPath = join(CONTENT, 'cdn-versions.json');
    const previous = existsSync(lockPath) ? JSON.parse(readFileSync(lockPath, 'utf8')) : {};

    const { files, collections } = buildSite(entries, KINDS, { version, commit, previous });

    const dist = join(ROOT, 'tools', 'content-cli', 'dist');
    rmSync(dist, { recursive: true, force: true });
    for (const file of files) {
      const target = join(dist, file.path);
      mkdirSync(dirname(target), { recursive: true });
      const bytes = Buffer.from(`${JSON.stringify(file.json)}\n`);

      // Les FRAGMENTS partent compressés, le manifeste en clair.
      //
      // Supabase Storage ne compresse pas à la volée et ne permet pas non plus
      // de poser `Content-Encoding` au téléversement (supabase-js#1883, demande
      // ouverte) : seuls `contentType` et `cacheControl` existent. La
      // décompression transparente par le client HTTP est donc hors d'atteinte,
      // et sans elle ce sont 423 Ko qui sortent au lieu de 70 — sur un quota
      // d'egress partagé avec la base et l'authentification.
      //
      // D'où du DEFLATE BRUT (RFC 1951), décompressé par l'app. Brut et pas
      // gzip parce que c'est exactement ce que `NSData.decompressed(using:
      // .zlib)` attend côté iOS, sans en-tête à retirer à la main. Il reste lu
      // par n'importe quel langage — zlib est partout, et un navigateur a
      // `DecompressionStream('deflate-raw')`. Ce qu'on perd, c'est le
      // `curl | jq` direct sur un fragment ; le manifeste, lui, reste lisible à
      // l'œil, et c'est celui qu'on inspecte à la main.
      if (file.immutable) {
        writeFileSync(`${target}.z`, deflateRawSync(bytes, { level: 9 }));
      } else {
        writeFileSync(target, bytes);
      }
    }

    writeFileSync(lockPath, `${JSON.stringify(collections, null, 2)}\n`);

    const changed = Object.entries(collections)
      .filter(([name]) => previous[name]?.version !== collections[name].version)
      .map(([name, info]) => `${name}→v${info.version}`);
    const published = entries.filter((e) => e.data.status === 'published').length;
    console.log(`build-cdn: publication ${commit} — ${published} entrée(s), ${files.length} fichier(s) dans dist/`);
    console.log(changed.length ? `  collections modifiées : ${changed.join(', ')}` : '  aucune collection modifiée');
    console.log('  déploiement : node cli.js deploy-cdn');
    ok = true;
    break;
  }
  case 'deploy-cdn': {
    // Téléverse dist/ vers le bucket public `content`. Les en-têtes de cache,
    // qui vivaient dans la configuration de l'hébergeur, se posent ici objet par objet : c'est la
    // seule différence de fond avec un hébergeur statique.
    const dist = join(ROOT, 'tools', 'content-cli', 'dist');
    if (!existsSync(dist)) {
      console.error('deploy-cdn: dist/ absent — lancer `node cli.js build-cdn` d’abord');
      ok = false;
      break;
    }
    try {
      const { uploadSite } = await import('./supabase-client.js');
      const count = await uploadSite(dist);
      console.log(`deploy-cdn: ${count} objet(s) téléversé(s) dans le bucket content`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
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
        const { listEditorDrafts, markEditorDraftsApplied } = await import('./supabase-client.js');
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
  // Le maillon qui manquait entre la veille et le fil : les faits `kind: "news"`
  // s'accumulaient dans content/inbox sans aucune sortie possible, faute de
  // schéma, de kind et de commande. Les faits `poi`, eux, étaient traités —
  // parce qu'ils avaient un tuyau.
  //
  // Cette commande ne RÉDIGE pas : elle pose des squelettes identifiés et
  // idempotents, marqués `needsRewrite`. La reformulation reste le seul maillon
  // confié à un modèle, et `check-publishable` refuse de publier ce qu'il n'a
  // pas rédigé.
  case 'pull-news':
    try {
      const { materializeNews } = await import('./facts-to-news.mjs');

      const inbox = join(CONTENT, 'inbox');
      const factFiles = existsSync(inbox)
        ? readdirSync(inbox).filter((f) => f.endsWith('.facts.json')).sort()
        : [];
      const facts = factFiles.flatMap((file) => {
        const data = JSON.parse(readFileSync(join(inbox, file), 'utf8'));
        return (data.facts ?? []).map((fact, index) => ({ ...fact, file, index }));
      });

      const newsDir = join(CONTENT, 'news');
      const existing = existsSync(newsDir)
        ? readdirSync(newsDir)
            .filter((name) => name.endsWith('.json'))
            .map((name) => ({
              path: join('content', 'news', name),
              data: JSON.parse(readFileSync(join(newsDir, name), 'utf8')),
            }))
        : [];

      const result = materializeNews(facts, existing);

      if (result.conflicts.length) {
        result.conflicts.forEach((c) => console.error(`  conflit: ${c.reason}\n           « ${c.claim?.slice(0, 80)}… »`));
        console.error("pull-news: rien matérialisé — corriger les faits d'inbox d'abord");
        ok = false;
        break;
      }

      if (dry) {
        result.writes.forEach(({ path, data }) => console.log(`  écrirait ${path}  [${data.confidence}] ${data.publishedAt}`));
        console.log(
          `pull-news --dry-run: ${result.writes.length} squelette(s), ` +
            `${result.alreadyMaterialized.length} déjà matérialisé(s), aucune écriture`,
        );
        ok = true;
        break;
      }

      if (result.writes.length) mkdirSync(newsDir, { recursive: true });
      result.writes.forEach(({ path, data }) => {
        writeFileSync(join(ROOT, path), `${JSON.stringify(data, null, 2)}\n`);
        console.log(`  écrit ${path}  [${data.confidence}] ${data.publishedAt}`);
      });

      // L'inbox est marquée pour la veille, PAS pour l'idempotence : celle-ci
      // vient de `processedFrom` (facts-to-news.mjs). Le drapeau sert au
      // data-scout, qui relit les faits déjà émis pour ne pas les re-signaler.
      const coveredByFile = new Map();
      for (const { fact } of result.covered) {
        if (!coveredByFile.has(fact.file)) coveredByFile.set(fact.file, new Set());
        coveredByFile.get(fact.file).add(fact.index);
      }
      // Note : un fait déjà marqué `processed` continue d'être relu à chaque run —
      // c'est ce qui permet à une fenêtre prolongée d'être révisée. Le drapeau ne
      // sert qu'à éviter que `data-scout` re-signale le fait, pas à l'exclure de
      // la matérialisation.
      let marked = 0;
      for (const [file, indices] of coveredByFile) {
        const path = join(inbox, file);
        const data = JSON.parse(readFileSync(path, 'utf8'));
        let touched = false;
        indices.forEach((index) => {
          if (data.facts[index].processed) return;
          data.facts[index].processed = true;
          touched = true;
          marked++;
        });
        if (touched) writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`);
      }

      console.log(
        `pull-news: ${result.writes.length} squelette(s) écrit(s), ` +
          `${result.alreadyMaterialized.length} déjà présent(s), ${marked} fait(s) marqué(s) — à rédiger puis committer`,
      );
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  // Sœur de `pull-news` : même mécanique, même absence de rédaction. Les faits
  // `kind: "online-event"` dormaient dans content/inbox faute d'un tuyau — le
  // schéma existait (online-event.schema.json), l'app savait déjà les
  // afficher, mais rien ne matérialisait jamais un fichier. Cette commande ne
  // RÉDIGE pas : elle pose des squelettes identifiés et idempotents, marqués
  // `needsRewrite`, et `check-publishable` refuse déjà de publier ce qu'elle
  // n'a pas rédigé.
  case 'pull-online-events':
    try {
      const { materializeOnlineEvents } = await import('./facts-to-online-event.mjs');

      const inbox = join(CONTENT, 'inbox');
      const factFiles = existsSync(inbox)
        ? readdirSync(inbox).filter((f) => f.endsWith('.facts.json')).sort()
        : [];
      const facts = factFiles.flatMap((file) => {
        const data = JSON.parse(readFileSync(join(inbox, file), 'utf8'));
        return (data.facts ?? []).map((fact, index) => ({ ...fact, file, index }));
      });

      const eventsDir = join(CONTENT, 'online-events');
      const existing = existsSync(eventsDir)
        ? readdirSync(eventsDir)
            .filter((name) => name.endsWith('.json'))
            .map((name) => ({
              path: join('content', 'online-events', name),
              data: JSON.parse(readFileSync(join(eventsDir, name), 'utf8')),
            }))
        : [];

      const result = materializeOnlineEvents(facts, existing);

      if (result.conflicts.length) {
        result.conflicts.forEach((c) => console.error(`  conflit: ${c.reason}\n           « ${c.claim?.slice(0, 80)}… »`));
        console.error("pull-online-events: rien matérialisé — corriger les faits d'inbox d'abord");
        ok = false;
        break;
      }

      // Une révision d'entrée PUBLIÉE change ce qui est en ligne. Elle est donc
      // annoncée champ par champ, en dry-run comme en écriture : c'est ce que le
      // relecteur de la PR doit voir sans dérouler un diff JSON.
      const describeRevision = ({ path, data, changes }) =>
        `  ${data.status === 'published' ? 'RÉVISE (PUBLIÉ)' : 'révise'} ${path}  ${data.startsAt} → ${data.endsAt}  [${changes.join(', ')}]`;

      if (dry) {
        result.writes.forEach(({ path, data }) => console.log(`  écrirait ${path}  [${data.confidence}] ${data.startsAt} → ${data.endsAt}`));
        result.updates.forEach((entry) => console.log(describeRevision(entry)));
        console.log(
          `pull-online-events --dry-run: ${result.writes.length} neuve(s), ${result.updates.length} révisée(s), ` +
            `${result.alreadyMaterialized.length} déjà à jour, aucune écriture`,
        );
        ok = true;
        break;
      }

      if (result.writes.length) mkdirSync(eventsDir, { recursive: true });
      result.writes.forEach(({ path, data }) => {
        writeFileSync(join(ROOT, path), `${JSON.stringify(data, null, 2)}\n`);
        console.log(`  écrit ${path}  [${data.confidence}] ${data.startsAt} → ${data.endsAt}`);
      });
      result.updates.forEach((entry) => {
        writeFileSync(join(ROOT, entry.path), `${JSON.stringify(entry.data, null, 2)}\n`);
        console.log(describeRevision(entry));
      });

      // L'inbox est marquée pour la veille, PAS pour l'idempotence : celle-ci
      // vient de `processedFrom` (facts-to-online-event.mjs). Le drapeau sert
      // au data-scout, qui relit les faits déjà émis pour ne pas les
      // re-signaler.
      const coveredByFile = new Map();
      for (const { fact } of result.covered) {
        if (!coveredByFile.has(fact.file)) coveredByFile.set(fact.file, new Set());
        coveredByFile.get(fact.file).add(fact.index);
      }
      // Note : un fait déjà marqué `processed` continue d'être relu à chaque run —
      // c'est ce qui permet à une fenêtre prolongée d'être révisée. Le drapeau ne
      // sert qu'à éviter que `data-scout` re-signale le fait, pas à l'exclure de
      // la matérialisation.
      let marked = 0;
      for (const [file, indices] of coveredByFile) {
        const path = join(inbox, file);
        const data = JSON.parse(readFileSync(path, 'utf8'));
        let touched = false;
        indices.forEach((index) => {
          if (data.facts[index].processed) return;
          data.facts[index].processed = true;
          touched = true;
          marked++;
        });
        if (touched) writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`);
      }

      console.log(
        `pull-online-events: ${result.writes.length} neuve(s), ${result.updates.length} révisée(s), ` +
          `${result.alreadyMaterialized.length} déjà à jour, ${marked} fait(s) marqué(s) — à relire puis committer`,
      );
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'moderate:list':
    try {
      const { listPendingContributions } = await import('./supabase-client.js');
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
      const { approveContribution } = await import('./supabase-client.js');
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
      const { rejectContribution } = await import('./supabase-client.js');
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
      const { shadowBanUser } = await import('./supabase-client.js');
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
      const { liftShadowBan } = await import('./supabase-client.js');
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
      const { getCommunityContributionsEnabled, setCommunityContributionsEnabled } = await import('./supabase-client.js');
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
    console.error('usage: cli.js <validate|check-publishable|translate --dry-run|publish --dry-run|deploy-rules|build-cdn|content-source [url|off]|pull-drafts [--file X]|pull-news [--dry-run]|pull-online-events [--dry-run]|moderate:list|moderate:approve <id>|moderate:reject <id>|shadow-ban <uid>|lift-shadow-ban <uid>|kill-switch [on|off]>');
    ok = false;
}

process.exit(ok ? 0 : 1);
