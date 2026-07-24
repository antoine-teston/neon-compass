#!/usr/bin/env node
// Surgically inserts one locale's translations into Localizable.xcstrings,
// touching only the exact byte range of each translated key's
// "localizations" object — never a whole-file JSON.parse()+dump, which
// silently reformats every untouched entry (Xcode's serializer uses
// 2-space indent and "key" : value with a space before AND after the
// colon; a generic stringify does not reproduce that). See Plan 6c's
// Global Constraints for why this matters.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const XCSTRINGS_PATH = join(ROOT, 'NeonCompass', 'Resources', 'Localizable.xcstrings');
const VALID_LOCALES = ['fr', 'es', 'it', 'de'];

function main() {
  const [, , locale, translationsPath] = process.argv;
  if (!VALID_LOCALES.includes(locale)) {
    throw new Error(`locale must be one of ${VALID_LOCALES.join(', ')}, got "${locale}"`);
  }
  if (!translationsPath) {
    throw new Error('usage: node apply-locale.js <locale> <translationsPath>');
  }

  const translations = JSON.parse(readFileSync(translationsPath, 'utf8'));
  let text = readFileSync(XCSTRINGS_PATH, 'utf8');
  const catalog = JSON.parse(text); // read-only: validates key coverage, never rewritten wholesale
  const allKeys = Object.keys(catalog.strings).sort();
  const providedKeys = Object.keys(translations).sort();

  const missing = allKeys.filter((k) => !providedKeys.includes(k));
  const extra = providedKeys.filter((k) => !allKeys.includes(k));
  if (missing.length > 0) {
    throw new Error(`missing translations for ${missing.length} key(s): ${missing.join(', ')}`);
  }
  if (extra.length > 0) {
    throw new Error(`translations file has ${extra.length} key(s) not in Localizable.xcstrings: ${extra.join(', ')}`);
  }

  let insertedCount = 0;
  let cursor = 0;
  for (const key of allKeys) {
    if (catalog.strings[key].localizations?.[locale]) {
      throw new Error(`"${key}" already has a "${locale}" localization — remove it first if you intend to replace it`);
    }

    // Index-based search (not one combined regex) because some keys have an
    // "extractionState" line between the key header and "localizations" —
    // a fixed-shape regex assuming "localizations" immediately follows the
    // key header misses those (confirmed against the real file: 18 of the
    // 104 keys have this extra line).
    const keyHeader = `"${key}" : {`;
    const keyIdx = text.indexOf(keyHeader, cursor);
    if (keyIdx === -1) throw new Error(`could not locate "${key}" in the catalog text`);

    const locHeader = '"localizations" : {';
    const locIdx = text.indexOf(locHeader, keyIdx);
    if (locIdx === -1) throw new Error(`could not locate a "localizations" block for "${key}"`);
    const locContentStart = locIdx + locHeader.length;

    // Closes both the "localizations" object (6-space indent) and the key's
    // own object (4-space indent) in one match — this exact 6-space/4-space
    // pairing only occurs once per key, since every nested "stringUnit"
    // object closes at 10-space/8-space indentation instead.
    const closeMarker = '\n      }\n    }';
    const closeIdx = text.indexOf(closeMarker, locContentStart);
    if (closeIdx === -1) throw new Error(`could not locate the end of the "localizations" block for "${key}"`);

    const value = translations[key];
    const escapedValue = JSON.stringify(value).slice(1, -1); // reuse JSON's own escaping — matches existing entries' style
    const newLocaleBlock =
      `,\n        "${locale}" : {\n          "stringUnit" : {\n` +
      `            "state" : "translated",\n            "value" : "${escapedValue}"\n` +
      `          }\n        }`;

    text = text.slice(0, closeIdx) + newLocaleBlock + text.slice(closeIdx);
    cursor = closeIdx + newLocaleBlock.length + closeMarker.length;
    insertedCount += 1;
  }

  JSON.parse(text); // fails loudly before anything is written if the splice broke JSON syntax
  writeFileSync(XCSTRINGS_PATH, text);
  console.log(`Inserted "${locale}" for ${insertedCount} keys.`);
}

main();
