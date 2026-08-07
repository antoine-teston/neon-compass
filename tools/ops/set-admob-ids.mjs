#!/usr/bin/env node
// Pose les identifiants AdMob réels dans les deux endroits qui les portent, et
// rend la ligne d'`app-ads.txt` qui va avec.
//
// **Pourquoi un script pour trois copier-coller.** Parce que les trois valeurs se
// ressemblent au point d'être interchangeables à l'œil, et que se tromper ne
// produit AUCUNE erreur : un App ID posé à la place d'une unité, ou une unité de
// bannière à la place de l'interstitiel, donne un inventaire qui ne remplit
// jamais. Le symptôme est « la pub ne s'affiche plus », jamais « mauvais
// identifiant ». La seule différence typographique entre un App ID et une unité
// est le séparateur : `~` pour l'application, `/` pour l'unité.
//
// Usage :
//   node tools/ops/set-admob-ids.mjs \
//     --app-id       ca-app-pub-1234567890123456~1234567890 \
//     --banner       ca-app-pub-1234567890123456/1111111111 \
//     --interstitial ca-app-pub-1234567890123456/2222222222 \
//     [--dry-run]

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

/// L'éditeur de test public de Google. Interdit en Release : c'est tout l'objet
/// de la manœuvre.
export const GOOGLE_TEST_PUBLISHER = '3940256099942544';

const APP_ID_SHAPE = /^ca-app-pub-(\d{16})~(\d{10})$/;
const UNIT_SHAPE = /^ca-app-pub-(\d{16})\/(\d{10})$/;

/// Valide les trois identifiants ensemble, parce que c'est ensemble qu'ils sont
/// faux. Rend `{ publisher, appId, banner, interstitial }` ou lève.
export function parseIds({ appId, banner, interstitial }) {
  const missing = Object.entries({ appId, banner, interstitial })
    .filter(([, v]) => !v)
    .map(([k]) => k);
  if (missing.length) {
    throw new Error(`identifiants manquants : ${missing.join(', ')}`);
  }

  if (!APP_ID_SHAPE.test(appId)) {
    const hint = UNIT_SHAPE.test(appId)
      ? " — c'est une UNITÉ (séparateur `/`), pas un App ID (séparateur `~`)"
      : '';
    throw new Error(`App ID mal formé : ${appId}${hint}`);
  }

  for (const [name, value] of [['banner', banner], ['interstitial', interstitial]]) {
    if (!UNIT_SHAPE.test(value)) {
      const hint = APP_ID_SHAPE.test(value)
        ? " — c'est un APP ID (séparateur `~`), pas une unité (séparateur `/`)"
        : '';
      throw new Error(`unité ${name} mal formée : ${value}${hint}`);
    }
  }

  if (banner === interstitial) {
    throw new Error('bannière et interstitiel portent la même unité — deux formats, deux unités');
  }

  const publishers = new Set([appId, banner, interstitial].map((v) => v.match(/ca-app-pub-(\d{16})/)[1]));
  if (publishers.size > 1) {
    throw new Error(`trois identifiants pour ${publishers.size} éditeurs différents : ${[...publishers].join(', ')}`);
  }

  const publisher = [...publishers][0];
  if (publisher === GOOGLE_TEST_PUBLISHER) {
    throw new Error(
      "ce sont les identifiants de TEST de Google. Les poser en Release ne rapporterait rien ; " +
      "ils restent le défaut jusqu'à la création du compte."
    );
  }

  return { publisher, appId, banner, interstitial };
}

/// La ligne d'`app-ads.txt`. `f08c47fec0942fa0` est l'identifiant de l'autorité
/// de certification de Google, constant pour tous les éditeurs.
export function appAdsTxt(publisher) {
  return `google.com, pub-${publisher}, DIRECT, f08c47fec0942fa0\n`;
}

const YAML_RELEASE = /(          # TODO\(ops\) : remplacer par l'App ID réel à la création du compte AdMob\.\n          GAD_APP_ID: ")[^"]*(")/;

export function patchProjectYml(source, appId) {
  if (!YAML_RELEASE.test(source)) {
    throw new Error("bloc Release introuvable dans project.yml — a-t-il déjà été posé ?");
  }
  return source.replace(
    YAML_RELEASE,
    `          # Posé par tools/ops/set-admob-ids.mjs. Doit rester cohérent avec la\n` +
    `          # branche Release d'AdUnits : un App ID et des unités de comptes\n` +
    `          # différents ne remplissent jamais, et ne lèvent pas.\n          GAD_APP_ID: "${appId}$2`
  );
}

const SWIFT_ELSE = /(    #else\n)[\s\S]*?(\n    #endif)/;

export function patchAdUnits(source, { banner, interstitial }) {
  if (!SWIFT_ELSE.test(source)) {
    throw new Error("branche #else introuvable dans AdUnits.swift");
  }
  const replacement =
    `$1` +
    `    // Posées par tools/ops/set-admob-ids.mjs. Le \`#if DEBUG\` au-dessus reste\n` +
    `    // la garantie qu'aucune de ces deux valeurs n'est servie en développement,\n` +
    `    // et AdUnitsTests le vérifie à chaque exécution de la suite.\n` +
    `    static let banner = "${banner}"\n` +
    `    static let interstitial = "${interstitial}"$2`;
  return source.replace(SWIFT_ELSE, replacement);
}

function parseArgv(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    if (flag === '--dry-run') { out.dryRun = true; continue; }
    const key = { '--app-id': 'appId', '--banner': 'banner', '--interstitial': 'interstitial' }[flag];
    if (key) { out[key] = argv[i + 1]; i += 1; }
  }
  return out;
}

function main() {
  const args = parseArgv(process.argv.slice(2));
  const ids = parseIds(args);

  const ymlPath = join(ROOT, 'project.yml');
  const swiftPath = join(ROOT, 'NeonCompass', 'Core', 'Ads', 'AdUnits.swift');
  const yml = patchProjectYml(readFileSync(ymlPath, 'utf8'), ids.appId);
  const swift = patchAdUnits(readFileSync(swiftPath, 'utf8'), ids);

  if (args.dryRun) {
    console.log('— essai à blanc, rien écrit —');
  } else {
    writeFileSync(ymlPath, yml);
    writeFileSync(swiftPath, swift);
    console.log(`project.yml et AdUnits.swift posés pour l'éditeur pub-${ids.publisher}.`);
  }

  console.log('\nContenu d\'app-ads.txt à servir à la RACINE du domaine développeur :\n');
  console.log(appAdsTxt(ids.publisher));
  console.log('Puis : xcodegen generate && xcodebuild -scheme NeonCompass \\');
  console.log("  -destination 'platform=iOS Simulator,name=iPhone 17' test");
  console.log('\nAdUnitsTests doit RESTER vert : il ne contrôle que la branche Debug,');
  console.log("qui n'est pas touchée ici. S'il rougit, un vrai identifiant a atterri");
  console.log('du mauvais côté du #if.');
}

if (process.argv[1] && process.argv[1].endsWith('set-admob-ids.mjs')) {
  try {
    main();
  } catch (error) {
    console.error(`\n✖ ${error.message}\n`);
    process.exit(1);
  }
}
