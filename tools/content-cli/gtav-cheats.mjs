// Extraction des codes de GTA V depuis la page Fandom « Cheats in GTA V ».
//
// Pourquoi une table d'alias curée plutôt qu'une déduplication automatique :
// la source nomme la même triche différemment d'une section à l'autre
// (« Fast Running » / « Fast Run », « Slidey Cars » / « Slippery Car Tires »).
// Une jointure sur le libellé donne 55 entrées au lieu de 36. Et aucune
// heuristique de similarité ne distingue « Slow Motion » de « Slow Motion
// Aim », qui sont deux triches distinctes — d'où le tri par longueur d'alias
// décroissante avant appariement.
//
// La source reste `gta.fandom.com` en mode api (registre §7). La fixture
// committée dans fixtures/ est la trace de provenance.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const CONTENT_DIR = join(HERE, '..', '..', 'content', 'cheats');

const PRIMARY_SOURCE = 'gta.fandom.com:Cheats in GTA V';

/** Jetons de la source vers jetons du schéma. La casse varie dans la source
 *  (« D-Pad Left » et « D-Pad left » coexistent), d'où la clé en minuscules. */
const BUTTON_TOKENS = {
  'd-pad up': 'up',
  'd-pad down': 'down',
  'd-pad left': 'left',
  'd-pad right': 'right',
  l1: 'l1', l2: 'l2', r1: 'r1', r2: 'r2',
  lb: 'lb', lt: 'lt', rb: 'rb', rt: 'rt',
  circle: 'circle', square: 'square', triangle: 'triangle',
  a: 'a', b: 'b', y: 'y',
};

/** `X` est ambigu : le bouton X sur Xbox, la croix sur PlayStation. La section
 *  d'origine tranche — jamais le jeton seul. */
function normalizeButton(token, mode) {
  const key = token.trim().toLowerCase();
  if (key === 'x') return mode === 'playstation' ? 'cross' : 'x';
  const mapped = BUTTON_TOKENS[key];
  if (!mapped) {
    throw new Error(`Jeton de bouton inconnu dans la source : ${JSON.stringify(token)}`);
  }
  return mapped;
}

const VEHICLES = [
  'Trashmaster', 'Stretch', 'Mallard', 'Sanchez', 'Comet', 'Buzzard Attack Chopper',
  'Caddy', 'Duster', 'Rapid GT', 'PCJ-600', 'BMX', 'Dodo', "Duke O'Death", 'Kraken',
];

export const CANONICAL_ALIASES = {
  invincibility: ['Invincibility'],
  max_health_armor: ['Max Health & Armor'],
  weapons: ['Weapons & Ammo', 'Weapons (', 'Give all Weapons'],
  parachute: ['Give Parachute', 'Parachute'],
  recharge_special: ['Recharge Special Ability'],
  fast_run: ['Fast Running', 'Fast Run'],
  fast_swim: ['Fast Swim'],
  super_jump: ['Super Jump'],
  skyfall: ['Skyfall'],
  explosive_melee: ['Explosive Melee Attacks'],
  flaming_bullets: ['Flaming Bullets'],
  explosive_ammo: ['Explosive Bullets', 'Explosive Ammo Rounds'],
  raise_wanted: ['Raise Wanted Level'],
  lower_wanted: ['Lower Wanted Level'],
  moon_gravity: ['Low Gravity', 'Moon Gravity'],
  slow_motion_aim: ['Slow Motion Aiming', 'Slow Motion Aim'],
  slow_motion: ['Slow Motion'],
  slippery_cars: ['Slidey Cars', 'Slippery Car Tires', 'Slippery Cars'],
  drunk_mode: ['Drunk Mode'],
  change_weather: ['Change weather', 'Change Weather'],
  director_mode: ['Director Mode'],
  black_cellphone: ['Black Cellphone'],
  ...Object.fromEntries(
    VEHICLES.map((v) => [
      `spawn_${v.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')}`,
      [`Spawn ${v}`],
    ]),
  ),
};

/** Alias les plus longs d'abord : sans ça « Slow Motion Aim » s'apparie à
 *  « Slow Motion » et les deux triches fusionnent. */
const ALIAS_ORDER = Object.keys(CANONICAL_ALIASES).sort(
  (a, b) =>
    Math.max(...CANONICAL_ALIASES[b].map((s) => s.length)) -
    Math.max(...CANONICAL_ALIASES[a].map((s) => s.length)),
);

function canonicalKey(label) {
  for (const key of ALIAS_ORDER) {
    if (CANONICAL_ALIASES[key].some((alias) => label.startsWith(alias))) return key;
  }
  return null;
}

/** Wikitext vers texte nu : liens, modèles, références, balises. */
function cleanLabel(s) {
  return s
    .replace(/\{\{Ref\|[^}]*\}\}/g, '')
    .replace(/\[\[[^\]|]*\|([^\]]*)\]\]/g, '$1')
    .replace(/\[\[([^\]]*)\]\]/g, '$1')
    .replace(/\{\{[^}]*\}\}/g, '')
    .replace(/'''?/g, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Les boutons apparaissent soit en image (`[[File:XBox B.png|25px|B]]`, dont
 *  le dernier paramètre est le texte alternatif), soit en gras (`'''RB'''`). */
function extractButtons(cell, mode) {
  const out = [];
  const re = /\[\[File:[^\]]*?\|([^|\]]+)\]\]|'''([^']+)'''/g;
  let m;
  while ((m = re.exec(cell)) !== null) {
    out.push(normalizeButton(m[1] ?? m[2], mode));
  }
  return out;
}

/** Forme canonique d'un mnémonique : `1-999-XXX-XXX`.
 *
 *  La source écrit une fois `(1-999 HOT-HANDS)` avec une espace là où toutes
 *  les autres entrées mettent un tiret — coquille confirmée par la seconde
 *  source, qui écrit `1-999-HOT-HANDS`. Les espaces deviennent donc des tirets
 *  plutôt que d'être supprimées : les effacer produirait `1-999HOT-HANDS`, une
 *  forme que rien ne reconnaît. */
function canonicalMnemonic(raw) {
  return cleanLabel(raw).replace(/\s+/g, '-').replace(/-{2,}/g, '-');
}

/** Le mnémonique est tantôt dans un `<small>`, tantôt entre parenthèses nues. */
function extractPhone(cell) {
  const text = cleanLabel(cell);
  const paren = text.match(/^([\d-]+)\s*\(([^)]+)\)$/);
  if (paren) return { kind: 'phone', number: paren[1], mnemonic: canonicalMnemonic(paren[2]) };
  const small = cell.match(/<small>\s*\(([^)]*)\)\s*<\/small>/s);
  const number = cleanLabel(cell.replace(/<small>.*?<\/small>/gs, ''));
  const code = { kind: 'phone', number };
  if (small) code.mnemonic = canonicalMnemonic(small[1]);
  return code;
}

/** Lignes `Effet | Code` d'une table wikitable. */
function tableRows(sectionBody) {
  const body = sectionBody.split('{|')[1]?.split('|}')[0] ?? '';
  const rows = [];
  for (const chunk of body.split('\n|-')) {
    const cells = chunk
      .split(/\n\|/)
      .map((c) => c.trim())
      .filter((c) => c && !c.startsWith('!') && !c.includes('class="wikitable"'));
    if (cells.length >= 2) rows.push([cells[0], cells[1]]);
  }
  return rows;
}

function sections(wikitext) {
  const parts = wikitext.split(/^(==[^=].*?==)\s*$/m);
  const out = new Map();
  for (let i = 1; i < parts.length; i += 2) {
    out.set(cleanLabel(parts[i].replace(/^=+|=+$/g, '')), parts[i + 1]);
  }
  return out;
}

export function parseCheats(wikitext) {
  const secs = sections(wikitext);
  const find = (predicate) => {
    for (const [title, body] of secs) if (predicate(title)) return body;
    throw new Error('Section attendue absente de la source — la page a été réorganisée');
  };

  const modeSections = [
    ['xbox', find((t) => t.startsWith('Xbox 360'))],
    ['playstation', find((t) => t.startsWith('PS3'))],
    ['pc', find((t) => t === 'PC')],
    ['phone', find((t) => t === 'Phone Cheats')],
  ];

  const cheats = new Map();
  for (const [mode, body] of modeSections) {
    for (const [rawLabel, rawCode] of tableRows(body)) {
      const label = cleanLabel(rawLabel);
      const key = canonicalKey(label);
      if (!key) throw new Error(`Libellé sans alias canonique : « ${label} » — table à compléter`);
      const entry = cheats.get(key) ?? { labels: [], codes: {} };
      if (!entry.labels.includes(label)) entry.labels.push(label);
      if (!entry.codes[mode]) {
        if (mode === 'phone') entry.codes[mode] = extractPhone(rawCode);
        else if (mode === 'pc') entry.codes[mode] = { kind: 'keyword', keyword: cleanLabel(rawCode) };
        else entry.codes[mode] = { kind: 'buttons', buttons: extractButtons(rawCode, mode) };
      }
      cheats.set(key, entry);
    }
  }
  return cheats;
}

/** L'ordre dans lequel les modes sont écrits, pour que le JSON produit ne
 *  dépende pas de l'ordre d'insertion — sinon un code ajouté par la seconde
 *  source apparaîtrait en queue d'objet et le diff serait illisible. */
const MODE_ORDER = ['playstation', 'xbox', 'pc', 'phone'];

function orderedCodes(codes) {
  return Object.fromEntries(
    MODE_ORDER.filter((mode) => codes[mode]).map((mode) => [mode, codes[mode]]),
  );
}

/** Écrit les fichiers de contenu.
 *
 *  Les codes viennent des sources et sont réécrits à chaque passage. Les textes
 *  d'effet sont notre rédaction : `effects` les fournit, et un fichier déjà
 *  présent les conserve — une réextraction ne doit jamais pouvoir écraser un
 *  texte relu.
 *
 *  `corroboration[clé]` porte le résultat du recoupement sur la seconde source :
 *  `{ verifiedBy: [...], status, addCodes? }`. `addCodes` fournit les codes que
 *  la source primaire n'a pas — ils ne sont pas fusionnés dans le parseur, qui
 *  ne doit décrire que ce que la page primaire contient réellement. Absent, la
 *  triche reste en `draft` mono-sourcée : `check-publishable` la refuserait à la
 *  publication, et c'est exactement le signal voulu. */
export function writeContent(cheats, { categories, effects, corroboration = {} }) {
  let written = 0;
  for (const [key, entry] of cheats) {
    const id = `cheat_gtav_${key}`;
    const path = join(CONTENT_DIR, `${id}.json`);
    let existing = {};
    try {
      existing = JSON.parse(readFileSync(path, 'utf8'));
    } catch {}
    const second = corroboration[key];
    const doc = {
      id,
      game: 'gtav',
      category: existing.category ?? categories[key],
      effect: existing.effect ?? effects[key],
      codes: orderedCodes({ ...entry.codes, ...(second?.addCodes ?? {}) }),
      blocksTrophies: false,
      status: second?.status ?? existing.status ?? 'draft',
      verifiedBy: second?.verifiedBy ?? existing.verifiedBy ?? [PRIMARY_SOURCE],
    };
    if (!doc.category) throw new Error(`Catégorie manquante pour ${key}`);
    if (!doc.effect) throw new Error(`Texte d'effet manquant pour ${key}`);
    writeFileSync(path, JSON.stringify(doc, null, 2) + '\n');
    written++;
  }
  return written;
}

// Exécution directe : `node gtav-cheats.mjs --write`
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { categories, effects } = await import('./gtav-cheats-editorial.mjs');
  let corroboration = {};
  try {
    corroboration = JSON.parse(
      readFileSync(join(HERE, 'gtav-cheats-corroboration.json'), 'utf8'),
    ).cheats;
  } catch {
    console.warn('gtav-cheats-corroboration.json absent : tout restera en draft mono-sourcé');
  }
  const wiki = readFileSync(join(HERE, 'fixtures', 'cheats-in-gtav.wiki'), 'utf8');
  const cheats = parseCheats(wiki);
  if (process.argv.includes('--write')) {
    console.log(`écrit : ${writeContent(cheats, { categories, effects, corroboration })} fichier(s)`);
  } else {
    console.log(`${cheats.size} triche(s) — ajouter --write pour écrire dans content/cheats/`);
  }
}
