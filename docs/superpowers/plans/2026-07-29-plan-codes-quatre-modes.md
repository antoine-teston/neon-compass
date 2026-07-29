# Section Codes — quatre modes de saisie — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer les 36 triches de GTA V dans l'écran Codes, saisissables selon les quatre modes réels du jeu (manette PlayStation, manette Xbox, mot-clé au clavier, numéro de téléphone), avec une bascule V/VI et un état d'attente pour GTA VI.

**Architecture:** `sequence` (qui exigeait `ps5` ET `xbox`) est remplacé par `codes`, un dictionnaire de modes à charge typée — séquence de boutons, mot-clé, ou numéro + mnémonique — dont toutes les entrées sont optionnelles. Un extracteur Node lit la page Fandom déjà au registre de sources et produit `content/cheats/*.json` ; `cli.js bundle` en projette un socle `seed-cheats.json` embarqué dans le binaire, de sorte que les codes fonctionnent au premier lancement et hors ligne. L'écran gagne deux sélecteurs de poids différents : le jeu dans la toolbar (changement de contexte), le mode de saisie en segmenté sous la recherche (loupe sur la même liste).

**Tech Stack:** Swift 6 (concurrence stricte), SwiftUI + Observation, SwiftData, Swift Testing. Outillage contenu en Node ESM (`node --test`), validation JSON Schema via Ajv.

**Spec:** `docs/superpowers/specs/2026-07-29-codes-quatre-modes-design.md`

## Global Constraints

- **iOS/iPadOS 26+**, universel iPhone + iPad. iPad de premier ordre : jamais un écran téléphone agrandi.
- **Swift 6, concurrence stricte.** SwiftUI seulement — pas d'UIKit sauf si une API l'impose, et alors enveloppé dans un seul fichier.
- **Liquid Glass** pour tout le chrome (`.glassEffect()` dans des `GlassEffectContainer`) ; le synthwave reste dans la couche contenu. Trois accents lumineux au maximum par écran.
- **Aucune chaîne codée en dur.** Toute chaîne visible passe par `NeonCompass/Resources/Localizable.xcstrings`, et elle est ajoutée dans **la même tâche** que la vue qui l'utilise, avec les 5 langues `en`, `fr`, `es`, `it`, `de`.
- **Le catalogue reste anglais-primaire** (`sourceLanguage: en`, `LocalizedText.en` requis). La bascule FR-primaire est un plan dédié : ne pas la commencer ici, ne pas inverser un seul site d'appel.
- **IP** : aucun asset Rockstar/Take-Two. Les noms de véhicules du jeu (Comet, Kraken, Duke O'Death) sont des identifiants factuels et sont conservés ; les **descriptions d'effet sont rédigées dans nos mots**, jamais recopiées de la source. `GamepadGlyph` n'utilise que des SF Symbols génériques — jamais un glyphe propriétaire Sony ou Microsoft.
- **Registre de sources** : `gta.fandom.com` en mode `api` uniquement (`api.php`). `redbull.com` reste hors registre — voir le spec. Ne pas ajouter de domaine.
- **Petits diffs, commits fréquents.** Avant de déclarer une tâche finie : `Scripts/test.sh` passe. Si ça échoue, coller la sortie.
- Générer le projet après toute modification de `project.yml` : `Scripts/build.sh` et `Scripts/test.sh` lancent déjà `xcodegen generate`.

---

## Structure des fichiers

**Créés**
- `tools/content-cli/gtav-cheats.mjs` — extraction Fandom → `content/cheats/*.json`. Une seule responsabilité : la source vers le contenu.
- `tools/content-cli/gtav-cheats.test.mjs` — tests du parseur sur une fixture wikitext.
- `tools/content-cli/fixtures/cheats-in-gtav.wiki` — extrait réel de la page source, figé.
- `content/cheats/cheat_gtav_*.json` — 36 fichiers.
- `NeonCompass/Core/Game.swift` — `enum Game` partagé (extrait de `NewsGame`).
- `NeonCompass/Core/Cheats/CheatCode.swift` — `CheatInputMode`, `CheatCode` et leur `Codable`.
- `NeonCompass/Core/Cheats/CheatLoader.swift` — chargement du socle embarqué.
- `NeonCompass/Core/System/Clipboard.swift` — la seule dépendance UIKit, isolée (`UIPasteboard`).
- `NeonCompass/Resources/Cheats/seed-cheats.json` — socle généré, jamais édité à la main.
- `NeonCompass/Features/Cheats/CheatCodeView.swift` — rend un `CheatCode` selon sa forme, à une taille donnée.
- `NeonCompass/Features/Cheats/CheatsUnavailableGroup.swift` — le groupe replié des codes absents du mode actif.
- `NeonCompass/Features/Cheats/CheatsEmptyGameView.swift` — état d'attente GTA VI.
- `NeonCompassTests/Cheats/CheatDecodingTests.swift`, `CheatLoaderTests.swift`.

**Modifiés**
- `content/schema/cheat.schema.json` — `codes` remplace `sequence`, `game` ajouté.
- `tools/content-cli/cli.js` — projection et vérification du socle cheats.
- `NeonCompass/Core/Cheats/Cheat.swift` — `codes`, `game` ; `Platform` supprimé.
- `NeonCompass/Core/Cheats/GamepadGlyph.swift` — `lb/lt/rb/rt`, signature simplifiée.
- `NeonCompass/Core/News/NewsItem.swift` — `NewsGame` devient un `typealias` de `Game`.
- `NeonCompass/Features/Cheats/CheatsModel.swift` — mode actif migré, jeu actif, partition.
- `NeonCompass/Features/Cheats/CheatsListView.swift`, `CheatCard.swift`, `CheatReaderView.swift`, `CheatsScreen.swift`.
- `NeonCompass/App/RootView.swift:154` — passe le socle.
- `project.yml` — référence de dossier `Resources/Cheats`.
- `NeonCompass/Resources/Localizable.xcstrings`.
- `NeonCompassTests/Cheats/CheatTests.swift` — son unique test décode un `sequence`.
- `NeonCompassTests/Cheats/GamepadGlyphTests.swift` — ses trois tests passent un `platform:`.
- `NeonCompassTests/Cheats/CheatsModelTests.swift` — ses cinq tests portent sur `activePlatform` et `filteredCheats`.

**Sur ces trois fichiers de tests existants** : ils compilent aujourd'hui et cessent de compiler dès la tâche 4. Aucun ne doit être supprimé sans que son intention soit reprise ailleurs — `CheatTests` garde l'invariant « les champs pipeline-only sont ignorés au décodage », `GamepadGlyphTests` celui « aucun glyphe propriétaire », `CheatsModelTests` ceux des favoris et du filtrage. Les tâches 4 et 6 disent où chacun atterrit.

**Supprimé**
- `content/cheats/cheat_sample_placeholder.json` — fixture qui ne décode pas, remplacée par du contenu réel.

---

### Task 1: Schéma v2 — `codes` et `game`

**Files:**
- Modify: `content/schema/cheat.schema.json` (remplacement complet)
- Modify: `content/cheats/cheat_sample_placeholder.json` (migré vers le nouveau schéma, supprimé en tâche 3)

**Interfaces:**
- Consumes: rien.
- Produces: le contrat JSON que les tâches 2, 3 et 4 respectent — clés `codes.playstation|xbox|pc|phone`, discriminant `kind` valant `buttons|keyword|phone`, champ `game` valant `gtav|leonida`, identifiant `^cheat_(gtav|leonida)_[a-z0-9_]+$`.

- [ ] **Step 1: Vérifier que rien d'autre ne dépend du placeholder**

```bash
grep -rn "cheat_sample_placeholder" . --exclude-dir=.git
```

Attendu : uniquement `content/cheats/cheat_sample_placeholder.json`. Si un test Node ou Swift le cite, le noter — la tâche 3 devra le remplacer plutôt que le supprimer.

- [ ] **Step 2: Réécrire le schéma**

Remplacer intégralement `content/schema/cheat.schema.json` par :

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "cheat.schema.json",
  "title": "Neon Compass Cheat",
  "type": "object",
  "required": ["id", "game", "category", "effect", "codes", "blocksTrophies", "status", "verifiedBy"],
  "additionalProperties": false,
  "properties": {
    "id": { "type": "string", "pattern": "^cheat_(gtav|leonida)_[a-z0-9_]+$" },
    "game": { "enum": ["gtav", "leonida"] },
    "category": { "enum": ["player", "weapons", "vehicles", "world", "misc"] },
    "effect": {
      "type": "object",
      "required": ["en"],
      "additionalProperties": false,
      "properties": {
        "en": { "type": "string", "minLength": 1 },
        "fr": { "type": "string" },
        "es": { "type": "string" },
        "it": { "type": "string" },
        "de": { "type": "string" }
      }
    },
    "codes": {
      "type": "object",
      "minProperties": 1,
      "additionalProperties": false,
      "properties": {
        "playstation": { "$ref": "#/$defs/buttonsCode" },
        "xbox": { "$ref": "#/$defs/buttonsCode" },
        "pc": { "$ref": "#/$defs/keywordCode" },
        "phone": { "$ref": "#/$defs/phoneCode" }
      }
    },
    "blocksTrophies": { "type": "boolean" },
    "status": { "enum": ["draft", "published"] },
    "verifiedBy": { "type": "array", "items": { "type": "string" } },
    "processedFrom": { "type": "string" }
  },
  "$defs": {
    "buttonsCode": {
      "type": "object",
      "required": ["kind", "buttons"],
      "additionalProperties": false,
      "properties": {
        "kind": { "const": "buttons" },
        "buttons": {
          "type": "array",
          "minItems": 1,
          "items": {
            "enum": [
              "up", "down", "left", "right",
              "cross", "circle", "square", "triangle",
              "a", "b", "x", "y",
              "l1", "l2", "r1", "r2",
              "lb", "lt", "rb", "rt"
            ]
          }
        }
      }
    },
    "keywordCode": {
      "type": "object",
      "required": ["kind", "keyword"],
      "additionalProperties": false,
      "properties": {
        "kind": { "const": "keyword" },
        "keyword": { "type": "string", "pattern": "^[A-Z0-9]+$" }
      }
    },
    "phoneCode": {
      "type": "object",
      "required": ["kind", "number"],
      "additionalProperties": false,
      "properties": {
        "kind": { "const": "phone" },
        "number": { "type": "string", "pattern": "^1-999-[0-9]+(-[0-9]+)*$" },
        "mnemonic": { "type": "string", "pattern": "^1-999-[A-Z0-9-]+$" }
      }
    }
  }
}
```

Deux contraintes portent du sens, pas de la décoration : `minProperties: 1` sur `codes` interdit une triche sans aucun moyen de la saisir (elle serait affichée sans être utilisable), et `additionalProperties: false` sur chaque `$defs` fait échouer une charge mal étiquetée — un `{"kind":"keyword","number":"…"}` doit être un échec bruyant, pas un mot-clé vide.

- [ ] **Step 3: Migrer le placeholder pour que la validation passe**

Remplacer `content/cheats/cheat_sample_placeholder.json` par :

```json
{
  "id": "cheat_gtav_sample_placeholder",
  "game": "gtav",
  "category": "misc",
  "effect": {
    "en": "Sample cheat used to validate the pipeline before launch.",
    "fr": "Cheat factice servant à valider le pipeline."
  },
  "codes": {
    "playstation": { "kind": "buttons", "buttons": ["up", "up", "circle", "l1"] },
    "xbox": { "kind": "buttons", "buttons": ["up", "up", "b", "lb"] },
    "pc": { "kind": "keyword", "keyword": "SAMPLE" },
    "phone": { "kind": "phone", "number": "1-999-123-456", "mnemonic": "1-999-SAMPLE" }
  },
  "blocksTrophies": false,
  "status": "draft",
  "verifiedBy": ["internal:fixture"]
}
```

Renommer le fichier : `git mv content/cheats/cheat_sample_placeholder.json content/cheats/cheat_gtav_sample_placeholder.json`

- [ ] **Step 4: Valider**

```bash
cd tools/content-cli && node cli.js validate
```

Attendu : `validate: N/N OK`, sans `FAIL`.

- [ ] **Step 5: Vérifier que le schéma refuse bien ce qu'il doit refuser**

Écrire un script jetable dans `tools/content-cli/` (il a les `node_modules`) et le supprimer après. **L'import doit être `ajv/dist/2020.js`** comme dans `cli.js:41` : le `ajv` par défaut ne connaît pas la méta-schéma draft 2020-12 et lève `no schema with key or ref`.

```js
import Ajv from 'ajv/dist/2020.js';
import { readFileSync } from 'node:fs';
const ajv = new Ajv({ allErrors: true });
const v = ajv.compile(JSON.parse(readFileSync('../../content/schema/cheat.schema.json', 'utf8')));
const base = {
  id: 'cheat_gtav_bad', game: 'gtav', category: 'misc', effect: { en: 'x' },
  blocksTrophies: false, status: 'draft', verifiedBy: [],
};
const cases = {
  'codes vide': { ...base, codes: {} },
  'charge mal étiquetée (keyword avec number)': { ...base, codes: { pc: { kind: 'keyword', number: '1-999-1' } } },
  'mode inconnu (switch)': { ...base, codes: { switch: { kind: 'buttons', buttons: ['up'] } } },
  'bouton inconnu': { ...base, codes: { xbox: { kind: 'buttons', buttons: ['up', 'nope'] } } },
  'séquence vide': { ...base, codes: { xbox: { kind: 'buttons', buttons: [] } } },
  'id sans jeu': { ...base, id: 'cheat_invincibility', codes: { pc: { kind: 'keyword', keyword: 'X' } } },
  'numéro hors format': { ...base, codes: { phone: { kind: 'phone', number: '555-1234' } } },
  'mot-clé en minuscules': { ...base, codes: { pc: { kind: 'keyword', keyword: 'comet' } } },
};
let wrong = 0;
for (const [name, doc] of Object.entries(cases)) {
  if (v(doc)) { console.log(`ACCEPTÉ À TORT  ${name}`); wrong++; }
  else console.log(`refusé  ${name}`);
}
const good = { ...base, id: 'cheat_gtav_ok', codes: { phone: { kind: 'phone', number: '1-999-266-38', mnemonic: '1-999-COMET' } } };
if (!v(good)) { console.log('REFUSÉ À TORT  cas valide', v.errors); wrong++; }
else console.log('accepté  cas valide (téléphone seul)');
process.exit(wrong === 0 ? 0 : 1);
```

Attendu : les huit cas refusés, le cas valide accepté, code de sortie 0.

- [ ] **Step 6: Commit**

```bash
git add content/schema/cheat.schema.json content/cheats/
git commit -m "$(cat <<'EOF'
feat(schema): les codes ont quatre modes de saisie, tous optionnels

sequence exigeait ps5 ET xbox. Huit des 36 triches de GTA V n'ont aucun
combo manette — elles étaient inexprimables. codes les remplace : un
dictionnaire par mode, dont la charge est étiquetée par kind parce qu'une
séquence de boutons, un mot-clé et un numéro de téléphone ne se rendent
pas de la même façon.

minProperties sur codes interdit une triche qu'on afficherait sans
pouvoir la saisir. L'identifiant porte le jeu : les deux jeux auront
leur invincibilité.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Extracteur Fandom → contenu

**Files:**
- Create: `tools/content-cli/gtav-cheats.mjs`
- Create: `tools/content-cli/gtav-cheats.test.mjs`
- Create: `tools/content-cli/fixtures/cheats-in-gtav.wiki`
- Modify: `tools/content-cli/package.json` (ajouter le test à la commande `test`)

**Interfaces:**
- Consumes: le contrat de schéma de la tâche 1.
- Produces: `parseCheats(wikitext) -> Map<canonicalKey, {labels: string[], codes: {playstation?, xbox?, pc?, phone?}}>` et `CANONICAL_ALIASES`, tous deux exportés et utilisés par les tests. Le CLI `node gtav-cheats.mjs --write` écrit `content/cheats/cheat_gtav_<clé>.json`.

- [ ] **Step 1: Figer la fixture depuis la source**

```bash
mkdir -p tools/content-cli/fixtures
curl -s -A "NeonCompass-ContentBot/1.0" \
  "https://gta.fandom.com/api.php?action=parse&page=Cheats%20in%20GTA%20V&prop=wikitext&format=json&formatversion=2" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>process.stdout.write(JSON.parse(s).parse.wikitext))" \
  > tools/content-cli/fixtures/cheats-in-gtav.wiki
wc -c tools/content-cli/fixtures/cheats-in-gtav.wiki
```

Attendu : environ 33 500 octets. La fixture est la trace de provenance exigée par la contrainte IP — elle est committée telle quelle, jamais retouchée à la main.

- [ ] **Step 2: Écrire le test d'abord**

Créer `tools/content-cli/gtav-cheats.test.mjs` :

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseCheats, CANONICAL_ALIASES } from './gtav-cheats.mjs';

const wiki = readFileSync(new URL('./fixtures/cheats-in-gtav.wiki', import.meta.url), 'utf8');

test('fusionne les libellés variables de la source en 36 triches canoniques', () => {
  const cheats = parseCheats(wiki);
  assert.equal(cheats.size, 36);
});

test('« Fast Running » et « Fast Run » sont la même triche', () => {
  const cheats = parseCheats(wiki);
  const entry = cheats.get('fast_run');
  assert.ok(entry, 'fast_run absent');
  assert.ok(entry.labels.length >= 2, `un seul libellé : ${entry.labels}`);
  assert.ok(entry.codes.playstation && entry.codes.pc);
});

test('« Slow Motion Aim » ne tombe pas dans « Slow Motion »', () => {
  const cheats = parseCheats(wiki);
  assert.ok(cheats.has('slow_motion'));
  assert.ok(cheats.has('slow_motion_aim'));
  assert.notDeepEqual(cheats.get('slow_motion').codes.pc, cheats.get('slow_motion_aim').codes.pc);
});

test('le téléphone couvre les 36 triches, la manette non', () => {
  const cheats = parseCheats(wiki);
  const withPhone = [...cheats.values()].filter((c) => c.codes.phone).length;
  const withPad = [...cheats.values()].filter((c) => c.codes.playstation || c.codes.xbox).length;
  assert.equal(withPhone, 36);
  assert.equal(withPad, 29);
});

test('les boutons sont normalisés en jetons du schéma', () => {
  const cheats = parseCheats(wiki);
  const allowed = new Set([
    'up', 'down', 'left', 'right',
    'cross', 'circle', 'square', 'triangle',
    'a', 'b', 'x', 'y',
    'l1', 'l2', 'r1', 'r2',
    'lb', 'lt', 'rb', 'rt',
  ]);
  for (const [key, c] of cheats) {
    for (const mode of ['playstation', 'xbox']) {
      for (const b of c.codes[mode]?.buttons ?? []) {
        assert.ok(allowed.has(b), `${key}/${mode} : jeton inconnu ${b}`);
      }
    }
  }
});

test('« X » est la croix sur PlayStation et le bouton X sur Xbox', () => {
  const cheats = parseCheats(wiki);
  const ps = [...cheats.values()].flatMap((c) => c.codes.playstation?.buttons ?? []);
  const xb = [...cheats.values()].flatMap((c) => c.codes.xbox?.buttons ?? []);
  assert.ok(ps.includes('cross'), 'aucune croix côté PlayStation');
  assert.ok(!ps.includes('a'), 'un bouton A a fui dans une séquence PlayStation');
  assert.ok(xb.includes('x'), 'aucun bouton X côté Xbox');
  assert.ok(!xb.includes('square'), 'un carré a fui dans une séquence Xbox');
});

test('le numéro de téléphone est séparé de son mnémonique', () => {
  const cheats = parseCheats(wiki);
  assert.deepEqual(cheats.get('spawn_comet').codes.phone, {
    kind: 'phone',
    number: '1-999-266-38',
    mnemonic: '1-999-COMET',
  });
});

test('le mode Réalisateur, dont le mnémonique est entre parenthèses nues, est parsé aussi', () => {
  const cheats = parseCheats(wiki);
  const phone = cheats.get('director_mode').codes.phone;
  assert.equal(phone.number, '1-999-57825368');
  assert.equal(phone.mnemonic, '1-999-LS-TALENT');
});

test('chaque alias canonique est réellement rencontré dans la source', () => {
  const cheats = parseCheats(wiki);
  for (const key of Object.keys(CANONICAL_ALIASES)) {
    assert.ok(cheats.has(key), `alias mort : ${key} n'apparaît nulle part dans la source`);
  }
});
```

Le dernier test est le garde-fou qui compte : une table d'alias curée pourrit en silence quand la source est réorganisée, et un alias mort fait disparaître une triche sans aucune erreur.

- [ ] **Step 3: Lancer le test, vérifier qu'il échoue**

```bash
cd tools/content-cli && node --test gtav-cheats.test.mjs
```

Attendu : échec sur `Cannot find module './gtav-cheats.mjs'`.

- [ ] **Step 4: Écrire l'extracteur**

Créer `tools/content-cli/gtav-cheats.mjs` :

```js
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

/** Le mnémonique est tantôt dans un `<small>`, tantôt entre parenthèses nues. */
function extractPhone(cell) {
  const text = cleanLabel(cell);
  const paren = text.match(/^([\d-]+)\s*\(([^)]+)\)$/);
  if (paren) return { kind: 'phone', number: paren[1], mnemonic: paren[2].replace(/\s+/g, '') };
  const small = cell.match(/<small>\s*\(([^)]*)\)\s*<\/small>/s);
  const number = cleanLabel(cell.replace(/<small>.*?<\/small>/gs, ''));
  const code = { kind: 'phone', number };
  if (small) code.mnemonic = cleanLabel(small[1]).replace(/\s+/g, '');
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

const PRIMARY_SOURCE = 'gta.fandom.com:Cheats in GTA V';

/** Écrit les fichiers de contenu.
 *
 *  Les codes viennent de la source et sont réécrits à chaque passage. Les
 *  textes d'effet sont notre rédaction : `effects` les fournit, et un fichier
 *  déjà présent les conserve — une réextraction ne doit jamais pouvoir écraser
 *  un texte relu.
 *
 *  `sources[clé]` porte le résultat du recoupement sur une seconde source
 *  (voir tâche 3) : `{ verifiedBy: [...], status: 'published' | 'draft' }`.
 *  Absent, la triche reste en `draft` avec la seule source primaire — ce que
 *  `check-publishable` refuserait de publier, et c'est voulu. */
export function writeContent(cheats, { categories, effects, sources = {} }) {
  let written = 0;
  for (const [key, entry] of cheats) {
    const id = `cheat_gtav_${key}`;
    const path = join(CONTENT_DIR, `${id}.json`);
    let existing = {};
    try {
      existing = JSON.parse(readFileSync(path, 'utf8'));
    } catch {}
    const corroboration = sources[key];
    const doc = {
      id,
      game: 'gtav',
      category: existing.category ?? categories[key],
      effect: existing.effect ?? effects[key],
      codes: entry.codes,
      blocksTrophies: false,
      status: corroboration?.status ?? existing.status ?? 'draft',
      verifiedBy: corroboration?.verifiedBy ?? existing.verifiedBy ?? [PRIMARY_SOURCE],
    };
    if (!doc.category) throw new Error(`Catégorie manquante pour ${key}`);
    if (!doc.effect) throw new Error(`Texte d'effet manquant pour ${key}`);
    writeFileSync(path, JSON.stringify(doc, null, 2) + '\n');
    written++;
  }
  return written;
}
```

- [ ] **Step 5: Lancer les tests jusqu'au vert**

```bash
cd tools/content-cli && node --test gtav-cheats.test.mjs
```

Attendu : 9 tests réussis. En cas d'échec sur le compte de 36, afficher le détail avant de toucher au parseur :

```bash
cd tools/content-cli && node -e "
import('./gtav-cheats.mjs').then(async (m) => {
  const { readFileSync } = await import('node:fs');
  const c = m.parseCheats(readFileSync('fixtures/cheats-in-gtav.wiki','utf8'));
  console.log('total', c.size);
  for (const [k,v] of c) console.log(k, Object.keys(v.codes).join(','), '|', v.labels.join(' / '));
});
"
```

- [ ] **Step 6: Brancher le test sur la commande du paquet**

Dans `tools/content-cli/package.json`, ajouter `gtav-cheats.test.mjs` à la liste de `test` :

```json
"test": "node --test ui/actions.test.mjs draft-to-poi.test.mjs facts-to-news.test.mjs source-policy.test.mjs gtav-cheats.test.mjs && npm run check"
```

- [ ] **Step 7: Commit**

```bash
git add tools/content-cli/gtav-cheats.mjs tools/content-cli/gtav-cheats.test.mjs \
        tools/content-cli/fixtures/cheats-in-gtav.wiki tools/content-cli/package.json
git commit -m "$(cat <<'EOF'
feat(content): extraire les 36 codes de GTA V, libellés fusionnés

La source nomme la même triche différemment selon la section : une
jointure sur le libellé donne 55 entrées pour 36 triches. D'où une table
d'alias curée, appariée du plus long au plus court — sans quoi « Slow
Motion Aim » se replie sur « Slow Motion » et deux triches distinctes
fusionnent.

Un test vérifie que chaque alias est réellement rencontré : une table
curée pourrit en silence quand la source est réorganisée, et un alias
mort fait disparaître une triche sans lever la moindre erreur.

writeContent ne réécrit jamais un texte d'effet existant. Les codes
viennent de la source, la rédaction est la nôtre.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Les 36 fichiers de contenu, effets rédigés dans nos mots

**Files:**
- Create: `content/cheats/cheat_gtav_<clé>.json` × 36
- Delete: `content/cheats/cheat_gtav_sample_placeholder.json`
- Create: `tools/content-cli/gtav-cheats-editorial.mjs` (catégories + textes, consommé par `writeContent`)

**Interfaces:**
- Consumes: `parseCheats`, `writeContent` de la tâche 2.
- Produces: 36 fichiers conformes au schéma de la tâche 1, que les tâches 5 et 6 lisent.

- [ ] **Step 1: Recouper les 36 triches sur une seconde source autorisée**

Ce n'est pas de la prudence décorative : `check-publishable` refuse déjà un cheat `published` dont `verifiedBy` compte moins de deux sources (`cli.js`, règle `kind === 'cheats'`). Or le socle de la tâche 5 embarque le contenu **indépendamment** de son statut. Livrer 36 codes mono-sourcés en `draft` ferait entrer dans le binaire exactement ce que la porte de publication refuse — le pipeline aurait raison et le binaire aurait tort.

Recouper, puis publier, est la seule issue cohérente. `gtaboom.com` est au registre en mode `allow` :

```bash
node --input-type=module -e "
import { policyFor } from './tools/content-cli/source-policy.mjs';
console.log(policyFor('https://www.gtaboom.com/gta-5-cheats-ps4/'));
"
```

Attendu : `mode: 'allow'`. Récupérer ensuite les pages de codes de cette source via `fetch-source.mjs` (qui porte déjà les réessais sur les 403 transitoires), et comparer code par code :

1. **Accord sur les deux sources** → `verifiedBy: ["gta.fandom.com:Cheats in GTA V", "gtaboom.com:GTA 5 cheats"]`, `status: "published"`.
2. **Désaccord sur un code** → ne rien publier de ce code. Le laisser en `draft` avec les deux valeurs consignées dans le message de commit, et le signaler dans le rapport de fin. Un combo faux est pire qu'un combo absent : il fait échouer la saisie sans dire pourquoi.
3. **La seconde source est muette sur un code** (cas attendu pour `director_mode` et `black_cellphone`, spécifiques au téléphone) → `status: "draft"`, une seule source. Il ne franchira pas la publication Firestore, mais il sera dans le socle — assumé et dit.

Cas particulier de `slow_motion_aim` : Fandom lui donne un combo Xbox et aucun combo PlayStation, là où les 27 autres triches à combo en ont deux. Si la seconde source fournit le combo PlayStation, l'ajouter et ajuster le compte attendu de la tâche 5 (28 → 29). Si elle est muette aussi, laisser `codes.playstation` absent : c'est alors un fait, pas une lacune de notre pipeline, et la tâche 8 l'affichera dans le groupe des codes indisponibles. **Ne jamais transposer un combo Xbox en combo PlayStation par symétrie** — les mappages ne sont pas des transpositions mécaniques l'un de l'autre.

La sortie de cette étape est un fichier `tools/content-cli/gtav-cheats-sources.json`, consommé par `writeContent` à l'étape 3 :

```json
{
  "spawn_comet": { "status": "published", "verifiedBy": ["gta.fandom.com:Cheats in GTA V", "gtaboom.com:GTA 5 cheats"] },
  "director_mode": { "status": "draft", "verifiedBy": ["gta.fandom.com:Cheats in GTA V"] }
}
```

Consigner dans le message de commit : le nombre de codes confirmés par deux sources, le nombre restés en `draft`, et tout désaccord rencontré.

- [ ] **Step 2: Écrire les catégories et les textes**

Créer `tools/content-cli/gtav-cheats-editorial.mjs`. Les textes sont notre rédaction : ils décrivent l'effet, ils ne recopient pas la source. Les noms de véhicules du jeu sont conservés — sans eux le code ne sert à rien.

```js
// Catégories et textes d'effet : la part éditoriale, séparée de l'extraction.
// Les descriptions sont rédigées dans nos mots (contrainte IP) ; les noms de
// véhicules sont des identifiants factuels et restent tels quels.

export const categories = {
  spawn_trashmaster: 'vehicles', spawn_stretch: 'vehicles', spawn_mallard: 'vehicles',
  spawn_sanchez: 'vehicles', spawn_comet: 'vehicles', spawn_buzzard_attack_chopper: 'vehicles',
  spawn_caddy: 'vehicles', spawn_duster: 'vehicles', spawn_rapid_gt: 'vehicles',
  spawn_pcj_600: 'vehicles', spawn_bmx: 'vehicles', spawn_dodo: 'vehicles',
  spawn_duke_o_death: 'vehicles', spawn_kraken: 'vehicles',

  invincibility: 'player', max_health_armor: 'player', parachute: 'player',
  recharge_special: 'player', fast_run: 'player', fast_swim: 'player',
  super_jump: 'player', skyfall: 'player', drunk_mode: 'player',

  weapons: 'weapons', flaming_bullets: 'weapons', explosive_ammo: 'weapons',
  explosive_melee: 'weapons',

  change_weather: 'world', moon_gravity: 'world', slow_motion: 'world',
  slow_motion_aim: 'world', slippery_cars: 'world',

  raise_wanted: 'misc', lower_wanted: 'misc', director_mode: 'misc',
  black_cellphone: 'misc',
};

export const effects = {
  spawn_trashmaster: { en: 'Drops a Trashmaster garbage truck next to you.', fr: 'Fait apparaître un camion-poubelle Trashmaster à côté de vous.' },
  spawn_stretch: { en: 'Drops a Stretch limousine next to you.', fr: 'Fait apparaître une limousine Stretch à côté de vous.' },
  spawn_mallard: { en: 'Drops a Mallard stunt biplane next to you.', fr: 'Fait apparaître un biplan de voltige Mallard à côté de vous.' },
  spawn_sanchez: { en: 'Drops a Sanchez dirt bike next to you.', fr: 'Fait apparaître une moto tout-terrain Sanchez à côté de vous.' },
  spawn_comet: { en: 'Drops a Comet sports car next to you.', fr: 'Fait apparaître une voiture de sport Comet à côté de vous.' },
  spawn_buzzard_attack_chopper: { en: 'Drops an armed Buzzard helicopter next to you.', fr: 'Fait apparaître un hélicoptère armé Buzzard à côté de vous.' },
  spawn_caddy: { en: 'Drops a Caddy golf cart next to you.', fr: 'Fait apparaître une voiturette de golf Caddy à côté de vous.' },
  spawn_duster: { en: 'Drops a Duster crop-dusting plane next to you.', fr: 'Fait apparaître un avion d’épandage Duster à côté de vous.' },
  spawn_rapid_gt: { en: 'Drops a Rapid GT sports car next to you.', fr: 'Fait apparaître une voiture de sport Rapid GT à côté de vous.' },
  spawn_pcj_600: { en: 'Drops a PCJ-600 motorcycle next to you.', fr: 'Fait apparaître une moto PCJ-600 à côté de vous.' },
  spawn_bmx: { en: 'Drops a BMX bike next to you.', fr: 'Fait apparaître un BMX à côté de vous.' },
  spawn_dodo: { en: 'Drops a Dodo seaplane next to you.', fr: 'Fait apparaître un hydravion Dodo à côté de vous.' },
  spawn_duke_o_death: { en: 'Drops the armoured Duke O’Death next to you.', fr: 'Fait apparaître la Duke O’Death blindée à côté de vous.' },
  spawn_kraken: { en: 'Drops a Kraken submarine next to you.', fr: 'Fait apparaître un sous-marin Kraken à côté de vous.' },

  invincibility: { en: 'Makes you immune to damage for five minutes. Enter it again to renew.', fr: 'Vous rend insensible aux dégâts pendant cinq minutes. À resaisir pour prolonger.' },
  max_health_armor: { en: 'Refills your health and armour to full.', fr: 'Remet votre santé et votre gilet au maximum.' },
  parachute: { en: 'Puts a parachute in your inventory.', fr: 'Ajoute un parachute à votre inventaire.' },
  recharge_special: { en: 'Refills your character’s special ability meter.', fr: 'Recharge la jauge de capacité spéciale de votre personnage.' },
  fast_run: { en: 'Doubles how fast you run.', fr: 'Double votre vitesse de course.' },
  fast_swim: { en: 'Doubles how fast you swim.', fr: 'Double votre vitesse de nage.' },
  super_jump: { en: 'Turns every jump into a huge leap.', fr: 'Transforme chaque saut en bond démesuré.' },
  skyfall: { en: 'Teleports you high above the map and drops you in free fall.', fr: 'Vous téléporte très haut au-dessus de la carte et vous lâche en chute libre.' },
  drunk_mode: { en: 'Blurs the picture and makes your character stagger.', fr: 'Trouble l’image et fait tituber votre personnage.' },

  weapons: { en: 'Gives you the full arsenal, ammunition included.', fr: 'Vous donne tout l’arsenal, munitions comprises.' },
  flaming_bullets: { en: 'Your bullets set what they hit on fire.', fr: 'Vos balles enflamment ce qu’elles touchent.' },
  explosive_ammo: { en: 'Your bullets detonate on impact.', fr: 'Vos balles explosent à l’impact.' },
  explosive_melee: { en: 'Your punches blow away whatever they land on.', fr: 'Vos coups de poing font exploser ce qu’ils atteignent.' },

  change_weather: { en: 'Switches the weather to the next setting in the cycle.', fr: 'Passe la météo au réglage suivant du cycle.' },
  moon_gravity: { en: 'Weakens gravity, so vehicles and bodies drift.', fr: 'Affaiblit la gravité : véhicules et corps se mettent à flotter.' },
  slow_motion: { en: 'Slows the whole world down. Stacks up to three times; a fourth entry turns it off.', fr: 'Ralentit le monde entier. Cumulable trois fois ; une quatrième saisie désactive.' },
  slow_motion_aim: { en: 'Slows time only while you aim. Stacks up to three times; a fourth entry turns it off.', fr: 'Ralentit le temps seulement pendant que vous visez. Cumulable trois fois ; une quatrième saisie désactive.' },
  slippery_cars: { en: 'Strips tyre grip, so every car slides.', fr: 'Supprime l’adhérence des pneus : toutes les voitures glissent.' },

  raise_wanted: { en: 'Adds one star to your wanted level.', fr: 'Ajoute une étoile à votre niveau de recherche.' },
  lower_wanted: { en: 'Removes one star from your wanted level.', fr: 'Retire une étoile à votre niveau de recherche.' },
  director_mode: { en: 'Opens Director Mode, the free-roam scene editor.', fr: 'Ouvre le mode Réalisateur, l’éditeur de scènes en roue libre.' },
  black_cellphone: { en: 'Switches your in-game phone to its black theme.', fr: 'Passe le téléphone du jeu sur son thème noir.' },
};
```

- [ ] **Step 3: Générer les 36 fichiers**

Ajouter en fin de `tools/content-cli/gtav-cheats.mjs` :

```js
// Exécution directe : `node gtav-cheats.mjs --write`
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { categories, effects } = await import('./gtav-cheats-editorial.mjs');
  let sources = {};
  try {
    sources = JSON.parse(readFileSync(join(HERE, 'gtav-cheats-sources.json'), 'utf8'));
  } catch {
    console.warn('gtav-cheats-sources.json absent : tout restera en draft mono-sourcé');
  }
  const wiki = readFileSync(join(HERE, 'fixtures', 'cheats-in-gtav.wiki'), 'utf8');
  const cheats = parseCheats(wiki);
  if (process.argv.includes('--write')) {
    console.log(`écrit : ${writeContent(cheats, { categories, effects, sources })} fichier(s)`);
  } else {
    console.log(`${cheats.size} triche(s) — ajouter --write pour écrire dans content/cheats/`);
  }
}
```

Puis :

```bash
cd tools/content-cli && node gtav-cheats.mjs --write \
  && git rm -q ../../content/cheats/cheat_gtav_sample_placeholder.json \
  && node cli.js validate && node cli.js check-publishable
```

Attendu : `écrit : 36 fichier(s)`, puis `validate: N/N OK` et `check-publishable: N/N OK`, sans `FAIL`. `ls ../../content/cheats/*.json | wc -l` doit donner 36.

Un `FAIL … published cheat requires verifiedBy >= 2 sources` signifie que l'étape 1 a marqué une triche `published` sans lui donner deux sources : corriger `gtav-cheats-sources.json`, pas le seuil.

- [ ] **Step 4: Relire les 36 textes — porte de conformité IP**

La détection de marques est déjà automatisée : `check-publishable` scanne le champ `effect` de toute langue contre `TRADEMARKS` (`GTA`, `Grand Theft Auto`, `Rockstar`, `Vice City`, `Leonida`, `Take-Two`), et l'étape 3 l'a lancé. Les noms de véhicules du jeu ne sont pas dans cette liste : ils sont attendus et légitimes.

Reste ce qu'aucune machine ne juge — la reprise de formulation. Écrire `tools/content-cli/check-originality.mjs` :

```js
// Garde-fou de la contrainte IP : aucune phrase d'effet ne doit se retrouver
// telle quelle dans la source. Ce n'est pas une preuve d'originalité — c'est la
// détection du copier-coller, que la relecture humaine, elle, laisse passer.
import { readFileSync } from 'node:fs';
import { effects } from './gtav-cheats-editorial.mjs';

const source = readFileSync(
  new URL('./fixtures/cheats-in-gtav.wiki', import.meta.url), 'utf8',
).toLowerCase();

let problems = 0;
for (const [key, text] of Object.entries(effects)) {
  for (const [lang, value] of Object.entries(text)) {
    if (source.includes(value.toLowerCase())) {
      console.error(`REPRIS TEL QUEL  ${key}.${lang} : ${value}`);
      problems++;
    }
  }
}
console.log(problems === 0 ? 'originalité : aucune reprise littérale' : `${problems} reprise(s)`);
process.exit(problems === 0 ? 0 : 1);
```

```bash
cd tools/content-cli && node check-originality.mjs
```

Attendu : `originalité : aucune reprise littérale`.

Reste enfin la relecture humaine, qu'aucun des deux contrôles ne remplace : le français lit-il comme du français, ou comme une traduction de l'anglais ? Les 36 textes se relisent d'une traite — c'est court, et c'est la seule étape qui juge la langue.

- [ ] **Step 5: Commit**

```bash
git add content/cheats tools/content-cli/gtav-cheats-editorial.mjs tools/content-cli/gtav-cheats.mjs \
        tools/content-cli/gtav-cheats-sources.json tools/content-cli/check-originality.mjs
git commit -m "$(cat <<'EOF'
content(cheats): les 36 codes de GTA V, recoupés et rédigés dans nos mots

Les combos, mots-clés et numéros sont des faits et viennent de la source.
Les descriptions d'effet sont notre rédaction — un contrôle vérifie
qu'aucune phrase de la source ne s'y retrouve. Les noms de véhicules du
jeu restent : un code qui ne dit pas ce qu'il fait apparaître ne sert à
rien.

Recoupés sur une seconde source autorisée, parce que check-publishable
exige deux sources pour publier un cheat et que le socle embarque
indépendamment du statut. Sans ce recoupement, le binaire aurait
transporté exactement ce que la porte de publication refuse.

La partie éditoriale vit dans son propre module : réextraire les codes
ne doit jamais pouvoir écraser un texte relu.

Le placeholder disparaît. Il n'existait que faute de contenu réel, et il
ne décodait pas.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Modèle Swift — `CheatInputMode`, `CheatCode`, `Game`

**Files:**
- Create: `NeonCompass/Core/Cheats/CheatCode.swift`
- Create: `NeonCompass/Core/Game.swift`
- Modify: `NeonCompass/Core/Cheats/Cheat.swift`
- Modify: `NeonCompass/Core/Cheats/GamepadGlyph.swift`
- Modify: `NeonCompass/Core/News/NewsItem.swift:42-57`
- Create: `NeonCompassTests/Cheats/CheatDecodingTests.swift`
- Modify: `NeonCompassTests/Cheats/GamepadGlyphTests.swift` (remplacement complet)
- Delete: `NeonCompassTests/Cheats/CheatTests.swift` (son invariant passe dans `CheatDecodingTests`)

**Interfaces:**
- Consumes: le contrat JSON de la tâche 1.
- Produces:
  - `enum CheatInputMode: String, CaseIterable, Codable, Sendable { case playstation, xbox, pc, phone }`
  - `enum CheatCode: Codable, Equatable, Sendable { case buttons([GamepadButton]); case keyword(String); case phone(number: String, mnemonic: String?) }`
  - `enum Game: String, CaseIterable, Codable, Sendable { case leonida; case reference = "gtav" }` avec `var shortLabel: String`
  - `struct Cheat { let id: String; let game: Game; let category: CheatCategory; let effect: LocalizedText; let codes: [CheatInputMode: CheatCode]; let blocksTrophies: Bool }`
  - `GamepadGlyph.systemImage(for button: GamepadButton) -> String` (le paramètre `platform:` disparaît)
  - `enum GamepadButton` gagne `lb, lt, rb, rt`
  - `typealias NewsGame = Game` reste disponible pour le fil d'actu.

- [ ] **Step 1: Écrire les tests de décodage d'abord**

Créer `NeonCompassTests/Cheats/CheatDecodingTests.swift` :

```swift
import Foundation
import Testing
@testable import NeonCompass

struct CheatDecodingTests {
    private func decode(_ json: String) throws -> Cheat {
        try JSONDecoder().decode(Cheat.self, from: Data(json.utf8))
    }

    private static let fourModes = """
    {"id":"cheat_gtav_spawn_comet","game":"gtav","category":"vehicles",
     "effect":{"en":"Drops a Comet sports car next to you."},
     "codes":{
       "playstation":{"kind":"buttons","buttons":["r1","circle","r2","right"]},
       "xbox":{"kind":"buttons","buttons":["rb","b","rt","right"]},
       "pc":{"kind":"keyword","keyword":"COMET"},
       "phone":{"kind":"phone","number":"1-999-266-38","mnemonic":"1-999-COMET"}},
     "blocksTrophies":false,"status":"draft","verifiedBy":["gta.fandom.com"]}
    """

    @Test func decodesAllFourModes() throws {
        let cheat = try decode(Self.fourModes)
        #expect(cheat.game == .reference)
        #expect(cheat.codes.count == 4)
        #expect(cheat.codes[.playstation] == .buttons([.r1, .circle, .r2, .right]))
        #expect(cheat.codes[.xbox] == .buttons([.rb, .b, .rt, .right]))
        #expect(cheat.codes[.pc] == .keyword("COMET"))
        #expect(cheat.codes[.phone] == .phone(number: "1-999-266-38", mnemonic: "1-999-COMET"))
    }

    @Test func decodesAPhoneOnlyCheat() throws {
        let cheat = try decode("""
        {"id":"cheat_gtav_director_mode","game":"gtav","category":"misc",
         "effect":{"en":"Opens Director Mode."},
         "codes":{"phone":{"kind":"phone","number":"1-999-57825368","mnemonic":"1-999-LS-TALENT"}},
         "blocksTrophies":false,"status":"draft","verifiedBy":[]}
        """)
        #expect(cheat.codes.count == 1)
        #expect(cheat.codes[.playstation] == nil)
    }

    @Test func phoneMnemonicIsOptional() throws {
        let cheat = try decode("""
        {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
         "codes":{"phone":{"kind":"phone","number":"1-999-111"}},
         "blocksTrophies":false,"status":"draft","verifiedBy":[]}
        """)
        #expect(cheat.codes[.phone] == .phone(number: "1-999-111", mnemonic: nil))
    }

    // Le socle embarqué et le cache SwiftData relisent ce que le modèle a écrit :
    // un encodage qui ne se relit pas vide l'écran au deuxième lancement, pas au
    // premier. C'est exactement le piège que Cheat.encode(to:) documente déjà
    // pour l'ancien dictionnaire de séquences.
    @Test func survivesAnEncodeDecodeRoundTrip() throws {
        let original = try decode(Self.fourModes)
        let reencoded = try JSONEncoder().encode(original)
        let again = try JSONDecoder().decode(Cheat.self, from: reencoded)
        #expect(again == original)
    }

    @Test func rejectsAnUnknownButton() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{"xbox":{"kind":"buttons","buttons":["up","nope"]}},
             "blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    @Test func rejectsAnUnknownInputMode() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{"switch":{"kind":"buttons","buttons":["up"]}},
             "blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    // Une triche sans aucun code s'afficherait sans pouvoir être saisie.
    @Test func rejectsACheatWithNoCodeAtAll() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{},"blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    @Test func rejectsAMislabelledPayload() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{"pc":{"kind":"keyword","number":"1-999-111"}},
             "blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    // Le vrai contenu, décodé pour de vrai : le schéma et le modèle Swift ont
    // déjà divergé une fois (lb/lt/rb/rt autorisés côté schéma, absents côté
    // Swift), et cette divergence-là ne se voyait dans aucun test unitaire.
    @Test func decodesEveryShippedCheatFile() throws {
        // #filePath = <racine>/NeonCompassTests/Cheats/CheatDecodingTests.swift
        let dir = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "content/cheats")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count == 36)
        for file in files {
            #expect(throws: Never.self, "\(file.lastPathComponent) ne décode pas") {
                try JSONDecoder().decode(Cheat.self, from: Data(contentsOf: file))
            }
        }
    }
}
```

Ce test lit `content/` depuis le disque et ne tournera donc que sur simulateur avec le dépôt monté — c'est le cas de `Scripts/test.sh`. La tâche 5 le double d'un test qui lit le socle **embarqué**, lequel vaut aussi sur un appareil.

- [ ] **Step 1b: Reprendre l'invariant de `CheatTests` puis le supprimer**

`NeonCompassTests/Cheats/CheatTests.swift` porte un seul test, `decodesCheatIgnoringPipelineOnlyFields` : il vérifie que `status` et `verifiedBy` sont ignorés au décodage. Cet invariant est déjà couvert par `CheatDecodingTests` ci-dessus — tous ses fixtures portent `status` et `verifiedBy`, et le décodage réussit. Ajouter cependant l'assertion explicite dans `decodesAllFourModes`, sinon l'invariant ne serait plus vérifié que par accident :

```swift
        // Reprise de CheatTests.decodesCheatIgnoringPipelineOnlyFields : les
        // champs pipeline-only du schéma n'ont pas d'équivalent dans le modèle
        // et doivent être ignorés sans erreur, pas provoquer un échec.
        #expect(cheat.effect.resolved(for: "en") == "Drops a Comet sports car next to you.")
```

Puis `git rm NeonCompassTests/Cheats/CheatTests.swift`.

- [ ] **Step 2: Remplacer le test des glyphes**

`NeonCompassTests/Cheats/GamepadGlyphTests.swift` existe et ses trois tests passent un argument `platform:` qui disparaît. Ils gardent une intention à préserver — « aucun glyphe propriétaire », « les lettres pour Xbox », « les gâchettes partagent leur glyphe » — reprise et élargie ci-dessous. Remplacer intégralement le fichier :

```swift
import Testing
import UIKit
@testable import NeonCompass

struct GamepadGlyphTests {
    // Reprise du test d'origine : uniquement des SF Symbols génériques, aucune
    // marque Sony ou Microsoft.
    @Test func faceButtonsNeverReferenceTrademarkedSymbols() {
        for button in [GamepadButton.cross, .circle, .square, .triangle] {
            #expect(!GamepadGlyph.systemImage(for: button).isEmpty)
        }
    }

    @Test func xboxFaceButtonsUseLetterGlyphs() {
        #expect(GamepadGlyph.systemImage(for: .a) == "a.circle")
        #expect(GamepadGlyph.systemImage(for: .b) == "b.circle")
    }

    // Le test d'origine comparait le même bouton entre deux plates-formes, ce
    // que la signature ne permet plus. L'invariant devient plus fort : les
    // gâchettes des deux familles partagent leur glyphe.
    @Test func shouldersShareTheirGlyphAcrossFamilies() {
        #expect(GamepadGlyph.systemImage(for: .l1) == GamepadGlyph.systemImage(for: .lb))
        #expect(GamepadGlyph.systemImage(for: .l2) == GamepadGlyph.systemImage(for: .lt))
        #expect(GamepadGlyph.systemImage(for: .r1) == GamepadGlyph.systemImage(for: .rb))
        #expect(GamepadGlyph.systemImage(for: .r2) == GamepadGlyph.systemImage(for: .rt))
    }
    // Un nom de SF Symbol erroné rend une Image vide : la carte affiche des
    // trous à la place de la séquence, et rien ne le signale au build.
    @Test func everyButtonResolvesToARealSFSymbol() {
        for button in GamepadButton.allCases {
            let name = GamepadGlyph.systemImage(for: button)
            #expect(!name.isEmpty)
            #expect(UIImage(systemName: name) != nil, "SF Symbol introuvable : \(name) pour \(button)")
        }
    }

    @Test func playstationAndXboxFacesShareTheirGeometry() {
        // Croix ↔ A, cercle ↔ B, carré ↔ X, triangle ↔ Y : même position sur la
        // manette, donc même forme affichée.
        #expect(GamepadGlyph.systemImage(for: .cross) == GamepadGlyph.systemImage(for: .a))
        #expect(GamepadGlyph.systemImage(for: .circle) == GamepadGlyph.systemImage(for: .b))
        #expect(GamepadGlyph.systemImage(for: .square) == GamepadGlyph.systemImage(for: .x))
        #expect(GamepadGlyph.systemImage(for: .triangle) == GamepadGlyph.systemImage(for: .y))
    }
}
```

`GamepadButton` doit gagner `CaseIterable` pour ce test.

- [ ] **Step 3: Lancer les tests, vérifier qu'ils échouent**

```bash
Scripts/test.sh -only-testing:NeonCompassTests/CheatDecodingTests
```

Attendu : échec de compilation — `Cheat` n'a ni `game` ni `codes`, `CheatInputMode` n'existe pas.

- [ ] **Step 4: Extraire `Game`**

Créer `NeonCompass/Core/Game.swift` :

```swift
import Foundation

/// Le jeu dont parle un contenu.
///
/// Extrait de `NewsGame` : le fil d'actu, les codes et — plus tard — les guides
/// désignent les mêmes deux jeux, et deux énumérations aux mêmes valeurs brutes
/// finissent toujours par diverger sur l'étiquette courte.
///
/// La valeur brute `gtav` porte le nom `reference` parce que c'est le rôle que
/// ce jeu joue dans l'app : la référence dont on tire ce qu'on sait avant la
/// sortie de son successeur.
enum Game: String, CaseIterable, Codable, Sendable {
    case leonida
    case reference = "gtav"

    var shortLabel: String {
        switch self {
        case .leonida: "VI"
        case .reference: "V"
        }
    }

    /// Tolérance héritée du fil d'actu, dont les entrées peuvent venir d'un
    /// pipeline plus ancien que l'app installée. Les codes n'en ont pas besoin
    /// — leur schéma contraint déjà l'énumération — mais partager le décodeur
    /// vaut mieux que dupliquer le type pour cette seule nuance.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Game(rawValue: raw) ?? .leonida
    }
}
```

Dans `NeonCompass/Core/News/NewsItem.swift`, supprimer les lignes 42-57 (l'`enum NewsGame` entier) et les remplacer par :

```swift
/// Le fil d'actu a été le premier à nommer les deux jeux ; le type vit
/// désormais dans `Core/Game.swift` et sert aussi aux codes.
typealias NewsGame = Game
```

- [ ] **Step 5: Écrire `CheatCode`**

Créer `NeonCompass/Core/Cheats/CheatCode.swift` :

```swift
import Foundation

/// Comment un code se saisit. Ce n'est pas une plate-forme : les combos sont
/// identiques de la PS3 à la PS5 et de la Xbox 360 aux Series, d'où
/// `playstation` et non `ps5`.
enum CheatInputMode: String, CaseIterable, Codable, Sendable {
    case playstation, xbox, pc, phone

    /// Le mode par défaut au premier lancement. Le téléphone est le seul où les
    /// 36 codes existent tous : un nouvel utilisateur ne tombe donc jamais sur
    /// une liste amputée d'un tiers sans comprendre pourquoi.
    static let `default`: CheatInputMode = .phone
}

/// Un code, dans la forme qu'impose son mode de saisie.
///
/// Union étiquetée plutôt que trois champs optionnels : les trois formes ne se
/// rendent pas de la même façon — une séquence de glyphes, un mot-clé à taper,
/// un numéro à composer — et deux d'entre elles se copient tandis que la
/// troisième n'a rien à copier. Un type qui rend ces cas exclusifs empêche la
/// vue d'avoir à traiter un état impossible.
enum CheatCode: Equatable, Sendable {
    case buttons([GamepadButton])
    case keyword(String)
    case phone(number: String, mnemonic: String?)
}

extension CheatCode: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, buttons, keyword, number, mnemonic
    }

    private enum Kind: String, Codable {
        case buttons, keyword, phone
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .buttons:
            let raw = try container.decode([String].self, forKey: .buttons)
            let buttons = try raw.map { token -> GamepadButton in
                guard let button = GamepadButton(rawValue: token) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .buttons, in: container,
                        debugDescription: "Bouton inconnu : \(token)"
                    )
                }
                return button
            }
            guard !buttons.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .buttons, in: container,
                    debugDescription: "Séquence de boutons vide"
                )
            }
            self = .buttons(buttons)
        case .keyword:
            self = .keyword(try container.decode(String.self, forKey: .keyword))
        case .phone:
            self = .phone(
                number: try container.decode(String.self, forKey: .number),
                mnemonic: try container.decodeIfPresent(String.self, forKey: .mnemonic)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .buttons(let buttons):
            try container.encode(Kind.buttons, forKey: .kind)
            try container.encode(buttons.map(\.rawValue), forKey: .buttons)
        case .keyword(let keyword):
            try container.encode(Kind.keyword, forKey: .kind)
            try container.encode(keyword, forKey: .keyword)
        case .phone(let number, let mnemonic):
            try container.encode(Kind.phone, forKey: .kind)
            try container.encode(number, forKey: .number)
            try container.encodeIfPresent(mnemonic, forKey: .mnemonic)
        }
    }
}

extension CheatCode {
    /// Ce qu'il y a à mettre dans le presse-papiers, ou `nil` quand il n'y a
    /// rien à copier : on ne copie pas une séquence de boutons.
    var copyableText: String? {
        switch self {
        case .buttons: nil
        case .keyword(let keyword): keyword
        case .phone(let number, _): number
        }
    }
}
```

- [ ] **Step 6: Réécrire `Cheat`**

Remplacer intégralement `NeonCompass/Core/Cheats/Cheat.swift` :

```swift
import Foundation

enum CheatCategory: String, CaseIterable, Codable, Sendable {
    case player, weapons, vehicles, world, misc
}

enum GamepadButton: String, CaseIterable, Codable, Sendable {
    case up, down, left, right
    case cross, circle, square, triangle
    case a, b, x, y
    case l1, l2, r1, r2
    // Les gâchettes Xbox. Le schéma les autorisait déjà ; leur absence ici
    // faisait lever `init(from:)` sur toute séquence Xbox, et l'écran Codes
    // restait vide sans qu'aucun test ne le dise.
    case lb, lt, rb, rt
}

/// Champs pipeline-only du schéma (`status`, `verifiedBy`) absents ici :
/// Codable ignore silencieusement les clés JSON inconnues au décodage
/// (même stratégie que POI, cf. plan 2).
struct Cheat: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let game: Game
    let category: CheatCategory
    let effect: LocalizedText
    let codes: [CheatInputMode: CheatCode]
    let blocksTrophies: Bool

    enum CodingKeys: String, CodingKey {
        case id, game, category, effect, codes, blocksTrophies
    }

    init(
        id: String,
        game: Game,
        category: CheatCategory,
        effect: LocalizedText,
        codes: [CheatInputMode: CheatCode],
        blocksTrophies: Bool
    ) {
        self.id = id
        self.game = game
        self.category = category
        self.effect = effect
        self.codes = codes
        self.blocksTrophies = blocksTrophies
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.game = try container.decode(Game.self, forKey: .game)
        self.category = try container.decode(CheatCategory.self, forKey: .category)
        self.effect = try container.decode(LocalizedText.self, forKey: .effect)
        self.blocksTrophies = try container.decode(Bool.self, forKey: .blocksTrophies)

        let raw = try container.decode([String: CheatCode].self, forKey: .codes)
        var codes: [CheatInputMode: CheatCode] = [:]
        for (key, code) in raw {
            guard let mode = CheatInputMode(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .codes, in: container,
                    debugDescription: "Mode de saisie inconnu : \(key)"
                )
            }
            codes[mode] = code
        }
        guard !codes.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .codes, in: container,
                debugDescription: "Aucun code : la triche serait affichée sans pouvoir être saisie"
            )
        }
        self.codes = codes
    }

    /// Miroir manuel de `init(from:)`. `[CheatInputMode: CheatCode]` n'a pas de
    /// clé `String`/`Int`, donc l'encodage `Dictionary` synthétisé produirait un
    /// tableau plat `[clé, valeur, clé, valeur, …]` au lieu de l'objet
    /// `{"phone": {…}}` que la lecture attend — cassant le round-trip dont
    /// dépendent le cache SwiftData de `ContentStore<Cheat>` et le socle
    /// embarqué.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(game, forKey: .game)
        try container.encode(category, forKey: .category)
        try container.encode(effect, forKey: .effect)
        try container.encode(blocksTrophies, forKey: .blocksTrophies)

        var raw: [String: CheatCode] = [:]
        for (mode, code) in codes { raw[mode.rawValue] = code }
        try container.encode(raw, forKey: .codes)
    }
}
```

`enum Platform` disparaît. Chercher tous ses usages avant de compiler :

```bash
grep -rn "Platform\b" NeonCompass/ NeonCompassTests/ | grep -v "platform="
```

Attendu, à corriger dans les tâches 6 à 10 : `CheatsModel`, `CheatsListView`, `CheatCard`, `CheatReaderView`, `CheatsScreen`, `GamepadGlyph`.

- [ ] **Step 7: Compléter `GamepadGlyph`**

Remplacer intégralement `NeonCompass/Core/Cheats/GamepadGlyph.swift` :

```swift
import Foundation

/// Uniquement des SF Symbols génériques (formes géométriques, lettres) —
/// jamais un logo ou glyphe propriétaire Sony/Microsoft.
///
/// Plus de paramètre `platform:` : le jeton porte déjà sa famille de manette.
/// `cross` et `a` sont deux cas distincts qui se rendent pareil, ce qui est
/// exactement l'information voulue — même position sur la manette, même forme
/// à l'écran — sans qu'un appelant ait à savoir quelle manette il affiche.
enum GamepadGlyph {
    static func systemImage(for button: GamepadButton) -> String {
        switch button {
        case .up: "dpad.up.filled"
        case .down: "dpad.down.filled"
        case .left: "dpad.left.filled"
        case .right: "dpad.right.filled"
        case .l1, .lb: "l1.button.roundedbottom.horizontal"
        case .l2, .lt: "l2.button.roundedtop.horizontal"
        case .r1, .rb: "r1.button.roundedbottom.horizontal"
        case .r2, .rt: "r2.button.roundedtop.horizontal"
        case .cross, .a: "a.circle"
        case .circle, .b: "b.circle"
        case .square, .x: "x.circle"
        case .triangle, .y: "y.circle"
        }
    }
}
```

Les symboles `lb.button.*` / `rt.button.*` existent dans SF Symbols, mais les gâchettes se lisent aussi bien avec les formes `l1`/`l2` déjà en place, et une seule famille de glyphes évite qu'une manette paraisse mieux traitée que l'autre. Si `GamepadGlyphTests` échoue sur un nom, c'est là qu'il faut regarder.

- [ ] **Step 8: Lancer les tests jusqu'au vert**

```bash
Scripts/test.sh -only-testing:NeonCompassTests/CheatDecodingTests \
                -only-testing:NeonCompassTests/GamepadGlyphTests
```

Attendu : tous verts, dont `decodesEveryShippedCheatFile` sur les 36 fichiers réels.

- [ ] **Step 9: Commit**

```bash
git add NeonCompass/Core NeonCompassTests/Cheats
git commit -m "$(cat <<'EOF'
fix(cheats): le modèle sait enfin décoder ce que le schéma autorise

GamepadButton n'avait pas lb/lt/rb/rt, que le schéma acceptait depuis
toujours. Toute séquence Xbox faisait lever init(from:), le fichier était
rejeté, et l'écran Codes restait vide — attribué à l'absence de contenu.
Un test décode maintenant les 36 fichiers réels : cette divergence-là ne
se voyait dans aucun test unitaire.

codes remplace sequence, en union étiquetée : une séquence de boutons, un
mot-clé et un numéro ne se rendent pas pareil, et deux d'entre eux se
copient. Rendre les cas exclusifs épargne à la vue un état impossible.

NewsGame devient Game, dans Core : le fil et les codes nomment les mêmes
deux jeux, et deux énumérations aux mêmes valeurs brutes divergent
toujours par l'étiquette.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Socle embarqué

**Files:**
- Modify: `tools/content-cli/cli.js` (projection + `checkSeeds`)
- Create: `NeonCompass/Resources/Cheats/seed-cheats.json` (généré)
- Create: `NeonCompass/Core/Cheats/CheatLoader.swift`
- Create: `NeonCompassTests/Cheats/CheatLoaderTests.swift`
- Modify: `project.yml`
- Modify: `NeonCompass/App/RootView.swift:154`

**Interfaces:**
- Consumes: les 36 fichiers de la tâche 3, `Cheat` de la tâche 4.
- Produces: `CheatLoader.bundled: [Cheat]`, passé en `seed:` par les tâches 5 et 6.

- [ ] **Step 1: Écrire le test du chargeur d'abord**

Créer `NeonCompassTests/Cheats/CheatLoaderTests.swift` :

```swift
import Testing
@testable import NeonCompass

struct CheatLoaderTests {
    // Sans socle, l'écran Codes est vide au premier lancement et hors ligne —
    // le contenu n'arrivant que du CDN ou de Firestore. C'est ce que ce test
    // garde : un `Resources/Cheats` mal déclaré dans project.yml rend
    // `bundled` vide sans casser le build.
    @Test func bundledSeedCarriesEveryCheat() {
        #expect(CheatLoader.bundled.count == 36)
    }

    @Test func bundledSeedIsAllGTAV() {
        #expect(CheatLoader.bundled.allSatisfy { $0.game == .reference })
    }

    @Test func everyBundledCheatHasAtLeastOneCode() {
        #expect(CheatLoader.bundled.allSatisfy { !$0.codes.isEmpty })
    }

    @Test func thePhoneIsTheOnlyModeThatCoversEverything() {
        let byMode = Dictionary(
            uniqueKeysWithValues: CheatInputMode.allCases.map { mode in
                (mode, CheatLoader.bundled.filter { $0.codes[mode] != nil }.count)
            }
        )
        #expect(byMode[.phone] == 36)
        #expect(byMode[.pc] == 34)
        #expect(byMode[.xbox] == 29)
        #expect(byMode[.playstation] == 28)
    }
}
```

Si la tâche 3 a comblé la lacune PlayStation depuis la source secondaire, ajuster `byMode[.playstation]` à 29 et le noter dans le commit.

- [ ] **Step 2: Lancer, vérifier l'échec**

```bash
Scripts/test.sh -only-testing:NeonCompassTests/CheatLoaderTests
```

Attendu : échec de compilation, `CheatLoader` inconnu.

- [ ] **Step 3: Projeter le socle depuis `cli.js`**

Dans `tools/content-cli/cli.js`, à côté de `COLLECTIONS_SEED` et `POI_SEED`, ajouter la constante de chemin :

```js
const CHEATS_SEED = join(ROOT, 'NeonCompass', 'Resources', 'Cheats', 'seed-cheats.json');
```

(Reprendre exactement la forme des deux constantes voisines — `ROOT` et `join` sont déjà en place.)

Ajouter la projection et son sérialiseur, près de `seedProjection` :

```js
/** Champs du cheat que le socle embarqué porte réellement — les autres sont
 *  pipeline-only et absents du modèle Swift. */
function cheatSeedProjection(cheat) {
  const { id, game, category, effect, codes, blocksTrophies } = cheat;
  return { id, game, category, effect, codes, blocksTrophies };
}

/** Tri par identifiant : l'ordre du socle ne doit pas dépendre de l'ordre de
 *  lecture du disque, sinon `check-seeds` signale une dérive à chaque machine.
 *
 *  Le kind est `cheats` — un kind est un répertoire de content/, pas un nom de
 *  schéma (le schéma, lui, s'appelle cheat.schema.json). */
function cheatsSeedContent(entries) {
  const cheats = entries
    .filter((e) => e.kind === 'cheats')
    .map((e) => cheatSeedProjection(e.data))
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return JSON.stringify(cheats, null, 2) + '\n';
}
```

Dans `bundleCollections`, écrire aussi le socle cheats (renommer la fonction en `bundleSeeds` si son nom devient trompeur, et mettre à jour son unique appelant dans le `switch`) :

```js
  writeFileSync(CHEATS_SEED, cheatsSeedContent(entries));
  console.log(`bundle: ${JSON.parse(cheatsSeedContent(entries)).length} cheat(s) -> ${CHEATS_SEED}`);
```

Dans `checkSeeds`, ajouter la même garde que pour `collections.json` :

```js
  if (cheatsSeedContent(entries) !== readFileSync(CHEATS_SEED, 'utf8')) {
    console.error(`FAIL ${CHEATS_SEED} est en retard sur content/cheats — lancer \`bundle\``);
    failures++;
  }
```

- [ ] **Step 4: Générer le socle**

```bash
mkdir -p NeonCompass/Resources/Cheats
cd tools/content-cli && node cli.js bundle && node cli.js check-seeds
```

Attendu : `bundle: 36 cheat(s) -> …/seed-cheats.json` puis `check-seeds: socles à jour`.

- [ ] **Step 5: Déclarer le dossier dans `project.yml`**

Dans la cible `NeonCompass`, ajouter l'exclusion et la référence de dossier, à côté de celles de `POI` :

```yaml
    sources:
      - path: NeonCompass
        excludes:
          - "Resources/MapArt/**"
          - "Resources/POI/**"
          - "Resources/Cheats/**"
      - path: NeonCompass/Resources/MapArt
        type: folder
      - path: NeonCompass/Resources/POI
        type: folder
      # Même raison que POI : sans `type: folder`, XcodeGen aplatit
      # seed-cheats.json à la racine du bundle et le `subdirectory: "Cheats"`
      # du chargeur ne le trouve jamais — l'écran Codes redeviendrait vide au
      # premier lancement, exactement le défaut que ce socle corrige.
      - path: NeonCompass/Resources/Cheats
        type: folder
```

- [ ] **Step 6: Écrire le chargeur**

Créer `NeonCompass/Core/Cheats/CheatLoader.swift` :

```swift
import Foundation

/// Socle embarqué des codes, projeté depuis `content/cheats/` par
/// `node cli.js bundle`. Jamais édité à la main.
///
/// Il existe parce que les codes doivent fonctionner au premier lancement et
/// hors ligne : la saisie immédiate ne tient pas si l'écran attend le réseau.
/// Et parce que les codes d'un jeu terminé ne changent plus.
enum CheatLoader {
    enum LoaderError: Error { case missingResource }

    /// Le repli sans sous-dossier n'est pas cosmétique : selon que
    /// `Resources/Cheats` est déclaré `type: folder` ou non dans project.yml,
    /// XcodeGen place le fichier dans `Cheats/` ou à plat à la racine du
    /// bundle. La variante folder est celle attendue, mais un lookup qui
    /// échoue ici vide silencieusement l'écran de tous ses codes.
    static func loadSeed(from bundle: Bundle = .main) throws -> [Cheat] {
        let url = bundle.url(forResource: "seed-cheats", withExtension: "json", subdirectory: "Cheats")
            ?? bundle.url(forResource: "seed-cheats", withExtension: "json")
        guard let url else { throw LoaderError.missingResource }
        return try JSONDecoder().decode([Cheat].self, from: Data(contentsOf: url))
    }

    /// Décodé paresseusement une seule fois pour tout le processus : l'écran
    /// Codes et l'amorçage du widget en ont tous deux besoin.
    static let bundled: [Cheat] = (try? loadSeed()) ?? []
}
```

- [ ] **Step 7: Passer le socle aux deux sites de construction**

`NeonCompass/App/RootView.swift:154` :

```swift
        let cheatStore = ContentStore<Cheat>.live(
            collectionName: "cheats",
            seed: CheatLoader.bundled,
            modelContext: modelContext
        )
```

`NeonCompass/Features/Cheats/CheatsScreen.swift:49` reçoit le même ajout. Les deux, sinon le widget et l'écran voient deux contenus différents — le défaut que le commentaire de `hydrateWidgetSummaryFromCache` documente déjà pour les POI.

- [ ] **Step 8: Lancer les tests jusqu'au vert**

```bash
Scripts/test.sh -only-testing:NeonCompassTests/CheatLoaderTests
```

Attendu : 4 tests verts. Un `bundledSeedCarriesEveryCheat` à 0 signifie que le lookup de ressource échoue : vérifier `project.yml` puis relancer `xcodegen generate`.

- [ ] **Step 9: Commit**

```bash
git add tools/content-cli/cli.js NeonCompass/Resources/Cheats project.yml \
        NeonCompass/Core/Cheats/CheatLoader.swift NeonCompass/App/RootView.swift \
        NeonCompass/Features/Cheats/CheatsScreen.swift NeonCompassTests/Cheats/CheatLoaderTests.swift
git commit -m "$(cat <<'EOF'
feat(cheats): les 36 codes sont embarqués dans le binaire

ContentStore<Cheat>.live était appelé sans seed sur ses deux sites, là
où les POI et les collections passent le leur : au premier lancement et
hors ligne, l'écran restait vide même le bug de décodage corrigé. Or un
écran de codes qui attend le réseau ne sert à rien manette en main, et
les codes d'un jeu terminé ne changent plus.

check-seeds couvre le nouveau socle : éditer un code sans régénérer
livrait un binaire en retard sur le contenu, sans que rien ne le dise.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `CheatsModel` — mode actif migré, jeu actif, partition

**Files:**
- Modify: `NeonCompass/Features/Cheats/CheatsModel.swift`
- Modify: `NeonCompassTests/Cheats/CheatsModelTests.swift` (remplacement complet — ses cinq tests portent sur `activePlatform` et `filteredCheats`, tous deux supprimés ; les trois qui concernent les favoris et le filtrage sont repris tels quels sous leur nouveau nom d'accès)

**Interfaces:**
- Consumes: `Cheat`, `CheatInputMode`, `Game`, `CheatLoader` des tâches 4 et 5.
- Produces, sur `CheatsModel` :
  - `var activeInputMode: CheatInputMode` (persistée, migrée depuis `cheatsActivePlatform`)
  - `var activeGame: Game` (persistée)
  - `var sections: [(category: CheatCategory, cheats: [Cheat])]` — les triches saisissables dans le mode actif, groupées, favorites d'abord dans chaque groupe
  - `var unavailableInActiveMode: [Cheat]` — celles qui passent les filtres mais n'ont pas de code dans le mode actif
  - `func modesAvailable(for cheat: Cheat) -> [CheatInputMode]`
  - `static let legacyPlatformKey = "cheatsActivePlatform"`

- [ ] **Step 1: Écrire les tests d'abord**

Créer `NeonCompassTests/Cheats/CheatsModelTests.swift` :

```swift
import Foundation
import SwiftData
import Testing
@testable import NeonCompass

@MainActor
struct CheatsModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: FavoriteCheat.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "CheatsModelTests.\(name)")!
        suite.removePersistentDomain(forName: "CheatsModelTests.\(name)")
        return suite
    }

    private func cheat(
        _ id: String,
        _ category: CheatCategory = .misc,
        game: Game = .reference,
        codes: [CheatInputMode: CheatCode]
    ) -> Cheat {
        Cheat(
            id: id, game: game, category: category,
            effect: LocalizedText(en: id, fr: nil, es: nil, it: nil, de: nil),
            codes: codes, blocksTrophies: false
        )
    }

    private func model(
        _ cheats: [Cheat],
        defaults suite: UserDefaults
    ) throws -> CheatsModel {
        CheatsModel(cheats: cheats, modelContext: try makeContext(), defaults: suite)
    }

    // La clé « ps5 » stockée par l'ancienne version doit continuer à se lire :
    // un renommage sec renverrait tout le monde au mode par défaut, et le
    // joueur qui avait choisi PlayStation retrouverait le téléphone sans avoir
    // rien touché.
    @Test func migratesTheStoredPS5Platform() throws {
        let suite = defaults("migrate-ps5")
        suite.set("ps5", forKey: CheatsModel.legacyPlatformKey)
        let sut = try model([], defaults: suite)
        #expect(sut.activeInputMode == .playstation)
    }

    @Test func migratesTheStoredXboxPlatform() throws {
        let suite = defaults("migrate-xbox")
        suite.set("xbox", forKey: CheatsModel.legacyPlatformKey)
        #expect(try model([], defaults: suite).activeInputMode == .xbox)
    }

    @Test func firstLaunchLandsOnTheOnlyCompleteMode() throws {
        #expect(try model([], defaults: defaults("fresh")).activeInputMode == .phone)
    }

    @Test func remembersTheChosenMode() throws {
        let suite = defaults("remember")
        let sut = try model([], defaults: suite)
        sut.activeInputMode = .pc
        #expect(try model([], defaults: suite).activeInputMode == .pc)
    }

    @Test func partitionsOnWhetherTheActiveModeHasACode() throws {
        let padAndPhone = cheat("pad", .player, codes: [
            .playstation: .buttons([.circle]), .phone: .phone(number: "1-999-1", mnemonic: nil),
        ])
        let phoneOnly = cheat("phone-only", .misc, codes: [
            .phone: .phone(number: "1-999-2", mnemonic: nil),
        ])
        let sut = try model([padAndPhone, phoneOnly], defaults: defaults("partition"))

        sut.activeInputMode = .playstation
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["pad"])
        #expect(sut.unavailableInActiveMode.map(\.id) == ["phone-only"])

        sut.activeInputMode = .phone
        #expect(sut.unavailableInActiveMode.isEmpty)
        #expect(sut.sections.flatMap(\.cheats).count == 2)
    }

    // L'ordre suit la déclaration de l'énumération, pas l'ordre d'arrivée du
    // contenu ni l'alphabet d'une langue — sinon la mise en page change d'une
    // locale à l'autre. Les entrées sont fournies dans l'ordre inverse exprès.
    @Test func groupsByCategoryInADeclarationOrder() throws {
        let sut = try model([
            cheat("m", .misc, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("v", .vehicles, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
            cheat("p", .player, codes: [.phone: .phone(number: "1-999-3", mnemonic: nil)]),
        ], defaults: defaults("sections"))
        #expect(sut.sections.map(\.category) == [.player, .vehicles, .misc])
        #expect(sut.sections.map(\.cheats.count) == [1, 1, 1])
    }

    @Test func keepsOnlyTheActiveGame() throws {
        let sut = try model([
            cheat("v", .misc, game: .reference, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("vi", .misc, game: .leonida, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
        ], defaults: defaults("game"))
        sut.activeGame = .reference
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["v"])
        sut.activeGame = .leonida
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["vi"])
    }

    @Test func searchMatchesTheEffectText() throws {
        let sut = try model([
            cheat("comet", .vehicles, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("kraken", .vehicles, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
        ], defaults: defaults("search"))
        sut.searchQuery = "krak"
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["kraken"])
    }

    // La recherche doit aussi porter sur les codes indisponibles : chercher une
    // triche et ne rien trouver parce qu'elle est reléguée dans le groupe replié
    // serait pire que de ne pas la filtrer du tout.
    @Test func searchAlsoFiltersTheUnavailableGroup() throws {
        let sut = try model([
            cheat("kraken", .vehicles, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("comet", .vehicles, codes: [.playstation: .buttons([.circle])]),
        ], defaults: defaults("search-unavailable"))
        sut.activeInputMode = .playstation
        sut.searchQuery = "krak"
        #expect(sut.unavailableInActiveMode.map(\.id) == ["kraken"])
        #expect(sut.sections.flatMap(\.cheats).isEmpty)
    }

    @Test func reportsWhichModesACheatSupports() throws {
        let sut = try model([], defaults: defaults("modes"))
        let c = cheat("x", .misc, codes: [
            .pc: .keyword("X"), .phone: .phone(number: "1-999-1", mnemonic: nil),
        ])
        #expect(sut.modesAvailable(for: c) == [.pc, .phone])
    }

    // MARK: - Repris de la version précédente du fichier
    //
    // Ces trois tests existaient et portaient sur `filteredCheats`, supprimé.
    // Leur intention — les favoris se basculent, se reflètent immédiatement, et
    // remontent en tête — n'a pas changé ; seul l'accès change.

    private var favoritable: [Cheat] {
        [
            cheat("a", .weapons, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("b", .weapons, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
        ]
    }

    @Test func favoritesAreToggleableAndPinnedFirst() throws {
        let sut = try model(favoritable, defaults: defaults("fav-pinned"))
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["a", "b"])
        sut.toggleFavorite(favoritable[1])
        #expect(sut.sections.flatMap(\.cheats).first?.id == "b")
    }

    @Test func favoriteCheatIDsReflectsToggleImmediately() throws {
        let sut = try model(favoritable, defaults: defaults("fav-ids"))
        let target = favoritable[0]
        #expect(!sut.favoriteCheatIDs.contains(target.id))
        sut.toggleFavorite(target)
        #expect(sut.favoriteCheatIDs.contains(target.id))
        sut.toggleFavorite(target)
        #expect(!sut.favoriteCheatIDs.contains(target.id))
    }

    @Test func filtersByCategory() throws {
        let sut = try model([
            cheat("a", .weapons, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("b", .misc, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
        ], defaults: defaults("categories"))
        sut.activeCategories = [.weapons]
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["a"])
    }
}
```

Le test `defaultPlatformIsPS5` de la version précédente n'est pas repris : le défaut change délibérément (`.phone`, cf. D5), et `firstLaunchLandsOnTheOnlyCompleteMode` le remplace. `platformPreferencePersistsAcrossInstances` devient `remembersTheChosenMode`, doublé de `migratesTheStoredPS5Platform` qui couvre ce que l'ancien test ne pouvait pas couvrir : la lecture d'une préférence écrite par la version précédente de l'app.

`LocalizedText` est déclaré dans `NeonCompass/Core/Map/POI.swift:26` et son initialiseur mémoire à mémoire n'a pas de valeur par défaut : les cinq langues sont à passer, comme le font déjà les autres suites de tests (`NeonCompassTests/Map/POIClustererTests.swift:8`).

- [ ] **Step 2: Lancer, vérifier l'échec**

```bash
Scripts/test.sh -only-testing:NeonCompassTests/CheatsModelTests
```

Attendu : échec de compilation — `activeInputMode`, `sections`, `unavailableInActiveMode` n'existent pas.

- [ ] **Step 3: Réécrire le modèle**

Remplacer `NeonCompass/Features/Cheats/CheatsModel.swift` :

```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CheatsModel {
    private static let inputModeKey = "cheatsActiveInputMode"
    private static let gameKey = "cheatsActiveGame"
    /// Clé de l'époque où le sélecteur portait sur une plate-forme et non sur un
    /// mode de saisie. Lue une fois, jamais écrite.
    static let legacyPlatformKey = "cheatsActivePlatform"

    private(set) var cheats: [Cheat]
    var searchQuery: String = ""
    var activeCategories: Set<CheatCategory>
    private(set) var favoriteCheatIDs: Set<String>

    var activeInputMode: CheatInputMode {
        didSet { defaults.set(activeInputMode.rawValue, forKey: Self.inputModeKey) }
    }

    var activeGame: Game {
        didSet { defaults.set(activeGame.rawValue, forKey: Self.gameKey) }
    }

    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private let widgetSummaryCoordinator: WidgetSummaryCoordinator?

    init(
        cheats: [Cheat],
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        widgetSummaryCoordinator: WidgetSummaryCoordinator? = nil
    ) {
        self.cheats = cheats
        self.modelContext = modelContext
        self.defaults = defaults
        self.widgetSummaryCoordinator = widgetSummaryCoordinator
        self.activeCategories = Set(CheatCategory.allCases)
        self.favoriteCheatIDs = Set(
            (try? modelContext.fetch(FetchDescriptor<FavoriteCheat>()))?.map(\.cheatID) ?? []
        )
        self.activeInputMode = Self.storedInputMode(in: defaults)
        self.activeGame = defaults.string(forKey: Self.gameKey)
            .flatMap(Game.init(rawValue:)) ?? .reference
        notifyWidgetFavoriteCheat()
    }

    /// La valeur de l'ancienne clé est encore la préférence de l'utilisateur :
    /// « ps5 » désignait déjà la famille PlayStation, dont les combos sont
    /// identiques de la PS3 à la PS5. Un renommage sec renverrait au mode par
    /// défaut quelqu'un qui avait choisi.
    private static func storedInputMode(in defaults: UserDefaults) -> CheatInputMode {
        if let raw = defaults.string(forKey: inputModeKey),
           let mode = CheatInputMode(rawValue: raw) {
            return mode
        }
        switch defaults.string(forKey: legacyPlatformKey) {
        case "ps5": return .playstation
        case "xbox": return .xbox
        default: return .default
        }
    }

    func updateCheats(_ newCheats: [Cheat]) {
        cheats = newCheats
        notifyWidgetFavoriteCheat()
    }

    func modesAvailable(for cheat: Cheat) -> [CheatInputMode] {
        CheatInputMode.allCases.filter { cheat.codes[$0] != nil }
    }

    /// Les triches du jeu actif qui passent catégories et recherche, sans égard
    /// au mode de saisie. Les deux collections publiques en dérivent, pour
    /// qu'aucune triche ne puisse tomber dans les deux ni dans aucune.
    private var matching: [Cheat] {
        let languageCode = currentLanguageCode
        return cheats.filter { cheat in
            cheat.game == activeGame
                && activeCategories.contains(cheat.category)
                && (searchQuery.isEmpty
                    || cheat.effect.resolved(for: languageCode)
                        .localizedCaseInsensitiveContains(searchQuery))
        }
    }

    /// Groupé par catégorie, dans l'ordre de déclaration de l'énumération —
    /// pas dans l'ordre alphabétique d'une langue, qui changerait la mise en
    /// page d'une locale à l'autre. Les catégories vides ne produisent pas de
    /// section.
    var sections: [(category: CheatCategory, cheats: [Cheat])] {
        let available = matching.filter { $0.codes[activeInputMode] != nil }
        return CheatCategory.allCases.compactMap { category in
            let group = available
                .filter { $0.category == category }
                .sorted { isFavorite($0) && !isFavorite($1) }
            return group.isEmpty ? nil : (category, group)
        }
    }

    /// Ce que le mode actif ne permet pas de saisir. Affiché, pas masqué :
    /// masquer ferait croire que ces triches n'existent pas.
    var unavailableInActiveMode: [Cheat] {
        matching.filter { $0.codes[activeInputMode] == nil }
    }

    func isFavorite(_ cheat: Cheat) -> Bool {
        favoriteCheatIDs.contains(cheat.id)
    }

    func toggleFavorite(_ cheat: Cheat) {
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            favoriteCheatIDs.remove(cheatID)
        } else {
            modelContext.insert(FavoriteCheat(cheatID: cheat.id))
            favoriteCheatIDs.insert(cheatID)
        }
        try? modelContext.save()
        notifyWidgetFavoriteCheat()
    }

    private func notifyWidgetFavoriteCheat() {
        let title = favoriteCheatIDs.first
            .flatMap { favoriteID in cheats.first { $0.id == favoriteID } }
            .map { $0.effect.resolved(for: currentLanguageCode) }
        widgetSummaryCoordinator?.updateFavoriteCheat(title)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
```

`filteredCheats` disparaît. Ses appelants — `CheatsScreen.swift:36` et `CheatsListView.swift:19` — sont repris aux tâches 8 et 10.

- [ ] **Step 4: Lancer jusqu'au vert**

```bash
Scripts/test.sh -only-testing:NeonCompassTests/CheatsModelTests
```

Attendu : 11 tests verts.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatsModel.swift NeonCompassTests/Cheats/CheatsModelTests.swift
git commit -m "$(cat <<'EOF'
feat(cheats): le mode de saisie remplace la plate-forme, et il se migre

« ps5 » désignait déjà la famille PlayStation — les combos sont
identiques de la PS3 à la PS5. La clé stockée est donc relue et
convertie, pas renommée : un renommage sec renvoyait au mode par défaut
quelqu'un qui avait choisi.

Le modèle partitionne au lieu de filtrer. Les deux collections publiques
dérivent du même ensemble filtré, si bien qu'aucune triche ne peut
tomber dans les deux ni disparaître entre les deux. Le défaut est le
téléphone : le seul mode où les 36 codes existent, donc le seul où un
premier lancement ne montre pas une liste amputée d'un tiers sans dire
pourquoi.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Rendu d'un code selon sa forme, et copie

**Files:**
- Create: `NeonCompass/Core/System/Clipboard.swift`
- Create: `NeonCompass/Features/Cheats/CheatCodeView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CheatCode`, `GamepadGlyph` de la tâche 4.
- Produces:
  - `enum Clipboard { static func copy(_ text: String) }`
  - `struct CheatCodeView: View { init(code: CheatCode, glyphSize: CGFloat, showsCopyButton: Bool) }` — utilisé par les tâches 8 et 10.

- [ ] **Step 1: Isoler la seule dépendance UIKit**

Créer `NeonCompass/Core/System/Clipboard.swift` :

```swift
import UIKit

/// Le presse-papiers n'a pas d'équivalent SwiftUI en écriture — `PasteButton`
/// ne fait que coller. C'est l'unique raison pour laquelle UIKit entre dans ce
/// projet, et il n'entre que par ce fichier.
enum Clipboard {
    @MainActor
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
```

- [ ] **Step 2: Ajouter les chaînes**

Dans `NeonCompass/Resources/Localizable.xcstrings`, ajouter ces clés, chacune avec ses 5 langues sur le modèle des clés existantes (`state: "translated"`) :

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `cheats.code.copy` | Copy | Copier | Copiar | Copia | Kopieren |
| `cheats.code.copied` | Copied | Copié | Copiado | Copiato | Kopiert |
| `cheats.code.pc.hint` | Type in the cheat console | À taper dans la console de triche | Escríbelo en la consola de trucos | Da digitare nella console dei trucchi | In der Cheat-Konsole eingeben |
| `cheats.code.phone.hint` | Dial on the in-game phone | À composer sur le téléphone du jeu | Márcalo en el teléfono del juego | Da comporre sul telefono di gioco | Im Spiel-Handy wählen |

- [ ] **Step 3: Écrire la vue**

Créer `NeonCompass/Features/Cheats/CheatCodeView.swift` :

```swift
import SwiftUI

/// Rend un code dans la forme qu'impose son mode de saisie.
///
/// Un seul endroit sait qu'une séquence se lit en glyphes, qu'un mot-clé se
/// tape et qu'un numéro se compose : la carte et le lecteur plein écran
/// partagent cette vue et ne diffèrent que par `glyphSize`.
struct CheatCodeView: View {
    let code: CheatCode
    let glyphSize: CGFloat
    var showsCopyButton: Bool = true

    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .center, spacing: glyphSize * 0.4) {
            switch code {
            case .buttons(let buttons):
                buttonRow(buttons)
            case .keyword(let keyword):
                textCode(keyword, hint: "cheats.code.pc.hint")
            case .phone(let number, let mnemonic):
                phoneCode(number, mnemonic: mnemonic)
            }
            if showsCopyButton, let text = code.copyableText {
                Spacer(minLength: 8)
                copyButton(text)
            }
        }
    }

    /// Enveloppé : une séquence de douze boutons dépasse la largeur d'un iPhone
    /// en compact, et une rangée qui déborde coupe la fin du code — c'est-à-dire
    /// la seule information que l'écran existe pour transmettre.
    private func buttonRow(_ buttons: [GamepadButton]) -> some View {
        HStack(spacing: glyphSize * 0.35) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                Image(systemName: GamepadGlyph.systemImage(for: button))
                    .font(.system(size: glyphSize))
                    .foregroundStyle(NCColor.neonCyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func textCode(_ text: String, hint: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(size: glyphSize * 0.8, weight: .heavy, design: .monospaced))
                .foregroundStyle(NCColor.neonCyan)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func phoneCode(_ number: String, mnemonic: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(number)
                .font(.system(size: glyphSize * 0.8, weight: .heavy, design: .monospaced))
                .foregroundStyle(NCColor.neonCyan)
            // Le mnémonique est ce qui rend un numéro mémorisable ; il est
            // secondaire à l'écran mais c'est lui qu'on retient.
            if let mnemonic {
                Text(mnemonic)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("cheats.code.phone.hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            Clipboard.copy(text)
            didCopy = true
        } label: {
            Label(
                didCopy ? "cheats.code.copied" : "cheats.code.copy",
                systemImage: didCopy ? "checkmark" : "doc.on.doc"
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(didCopy ? NCColor.neonCyan : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(didCopy ? "cheats.code.copied" : "cheats.code.copy")
        .sensoryFeedback(.success, trigger: didCopy)
    }
}
```

- [ ] **Step 4: Vérifier la compilation et l'aperçu**

```bash
Scripts/build.sh
```

Attendu : `BUILD SUCCEEDED` pour les deux schémas.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/System/Clipboard.swift \
        NeonCompass/Features/Cheats/CheatCodeView.swift \
        NeonCompass/Resources/Localizable.xcstrings
git commit -m "$(cat <<'EOF'
feat(cheats): un code se rend selon la façon dont on le saisit

Une séquence se lit en glyphes, un mot-clé se tape, un numéro se compose
— et deux des trois se copient. Une seule vue porte cette connaissance ;
la carte et le lecteur plein écran ne diffèrent plus que par la taille.

La rangée de glyphes est enveloppée : douze boutons dépassent la largeur
d'un iPhone en compact, et une rangée qui déborde coupe la fin du code,
seule information que l'écran existe pour transmettre.

UIPasteboard n'a pas d'équivalent SwiftUI en écriture. C'est la seule
raison pour laquelle UIKit entre ici, et il n'entre que par un fichier.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: La carte et la liste

**Files:**
- Modify: `NeonCompass/Features/Cheats/CheatCard.swift`
- Modify: `NeonCompass/Features/Cheats/CheatsListView.swift`
- Create: `NeonCompass/Features/Cheats/CheatsUnavailableGroup.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CheatsModel` (tâche 6), `CheatCodeView` (tâche 7).
- Produces: `CheatCard(cheat:code:isFavorite:onTap:onToggleFavorite:)`, `CheatsUnavailableGroup(cheats:model:onSelect:)`.

- [ ] **Step 1: Ajouter les chaînes**

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `cheats.mode.playstation` | PlayStation controller | Manette PlayStation | Mando PlayStation | Controller PlayStation | PlayStation-Controller |
| `cheats.mode.xbox` | Xbox controller | Manette Xbox | Mando Xbox | Controller Xbox | Xbox-Controller |
| `cheats.mode.pc` | Keyboard | Clavier | Teclado | Tastiera | Tastatur |
| `cheats.mode.phone` | In-game phone | Téléphone du jeu | Teléfono del juego | Telefono di gioco | Spiel-Handy |
| `cheats.mode.playstation.short` | PS | PS | PS | PS | PS |
| `cheats.mode.xbox.short` | Xbox | Xbox | Xbox | Xbox | Xbox |
| `cheats.mode.pc.short` | Keyboard | Clavier | Teclado | Tastiera | Tastatur |
| `cheats.mode.phone.short` | Phone | Téléphone | Teléfono | Telefono | Handy |
| `cheats.mode.picker` | Input method | Mode de saisie | Método de entrada | Modalità di inserimento | Eingabeart |
| `cheats.category.player` | Character | Personnage | Personaje | Personaggio | Charakter |
| `cheats.category.weapons` | Weapons | Armes | Armas | Armi | Waffen |
| `cheats.category.vehicles` | Vehicles | Véhicules | Vehículos | Veicoli | Fahrzeuge |
| `cheats.category.world` | World | Monde | Mundo | Mondo | Welt |
| `cheats.category.misc` | Other | Divers | Otros | Vari | Sonstiges |
| `cheats.unavailable.title` | %lld codes need another input method | %lld codes passent par un autre mode de saisie | %lld códigos usan otro método de entrada | %lld codici usano un'altra modalità | %lld Codes brauchen eine andere Eingabeart |
| `cheats.unavailable.switch` | Switch to %@ | Basculer sur %@ | Cambiar a %@ | Passa a %@ | Zu %@ wechseln |
| `cheats.footnote.safe` | None of these codes block 100% completion. They wear off, and the in-game phone doesn't remember them — re-enter to renew. | Aucun de ces codes n'empêche le 100 %. Leur effet expire, et le téléphone du jeu ne les mémorise pas : à resaisir pour renouveler. | Ninguno de estos códigos impide el 100 %. Su efecto caduca y el teléfono del juego no los recuerda: vuelve a introducirlos. | Nessuno di questi codici impedisce il 100 %. L'effetto scade e il telefono di gioco non li memorizza: reinseriscili. | Keiner dieser Codes verhindert 100 %. Die Wirkung endet, und das Spiel-Handy merkt sie sich nicht — neu eingeben. |
| `cheats.search.placeholder` | *(existe déjà — ne pas dupliquer)* | | | | |

Les clés `cheats.platform.picker`, `cheats.platform.ps5` et `cheats.platform.xbox` deviennent orphelines : les supprimer du catalogue dans cette même tâche.

- [ ] **Step 2: Réécrire la carte**

Remplacer `NeonCompass/Features/Cheats/CheatCard.swift` :

```swift
import SwiftUI

struct CheatCard: View {
    let cheat: Cheat
    /// Le code du mode actif, résolu par l'appelant. La carte n'a pas à
    /// connaître le mode : elle affiche le code qu'on lui donne.
    let code: CheatCode
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(cheat.effect.resolved(for: currentLanguageCode))
                        .font(NCTypography.body.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? NCColor.sunsetOrange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite ? "cheats.favorite.remove" : "cheats.favorite.add")
                }

                CheatCodeView(code: code, glyphSize: 18)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
```

Le badge `blocksTrophies` quitte la carte : il ne se déclencherait jamais pour GTA V, et l'information utile — l'inverse — vit désormais une seule fois en pied de liste. Ajouter aussi `cheats.favorite.add` / `cheats.favorite.remove` au catalogue (en : *Add to favourites* / *Remove from favourites* ; fr : *Ajouter aux favoris* / *Retirer des favoris* ; es : *Añadir a favoritos* / *Quitar de favoritos* ; it : *Aggiungi ai preferiti* / *Rimuovi dai preferiti* ; de : *Zu Favoriten hinzufügen* / *Aus Favoriten entfernen*).

- [ ] **Step 3: Écrire le groupe des codes indisponibles**

Créer `NeonCompass/Features/Cheats/CheatsUnavailableGroup.swift` :

```swift
import SwiftUI

/// Les triches que le mode actif ne permet pas de saisir.
///
/// Repliées en bas de liste plutôt que masquées : huit des trente-six codes de
/// GTA V n'ont aucun combo manette, et les masquer ferait croire à un joueur
/// console qu'ils n'existent pas. Repliées plutôt qu'en ligne : la liste
/// dépliée sert le scan rapide, qui est la raison d'être de l'écran.
struct CheatsUnavailableGroup: View {
    let cheats: [Cheat]
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void

    @State private var isExpanded = false

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("cheats.unavailable.title \(cheats.count)")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(cheats) { cheat in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cheat.effect.resolved(for: currentLanguageCode))
                            .font(NCTypography.body)
                            .foregroundStyle(.white.opacity(0.75))
                        // Le tap ne se contente pas d'informer : il emmène
                        // l'utilisateur dans le mode où le code existe.
                        ForEach(model.modesAvailable(for: cheat), id: \.self) { mode in
                            Button {
                                model.activeInputMode = mode
                                onSelect(cheat)
                            } label: {
                                // String(localized:) résout d'abord le nom du
                                // mode, puis l'injecte dans le %@ du gabarit :
                                // interpoler un Text dans une LocalizedStringKey
                                // ne produit pas la substitution attendue.
                                Label(
                                    "cheats.unavailable.switch \(String(localized: mode.label))",
                                    systemImage: mode.symbolName
                                )
                                .font(.caption.bold())
                            }
                            .buttonStyle(.glassProminent)
                            .tint(NCColor.sunsetViolet)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

extension CheatInputMode {
    /// Nom complet, pour les phrases et l'accessibilité.
    var label: LocalizedStringResource {
        switch self {
        case .playstation: "cheats.mode.playstation"
        case .xbox: "cheats.mode.xbox"
        case .pc: "cheats.mode.pc"
        case .phone: "cheats.mode.phone"
        }
    }

    /// Nom court, pour le segmenté : quatre segments dont l'un dirait
    /// « PlayStation » en entier tronqueraient tous les autres en largeur
    /// compacte.
    var shortLabel: LocalizedStringResource {
        switch self {
        case .playstation: "cheats.mode.playstation.short"
        case .xbox: "cheats.mode.xbox.short"
        case .pc: "cheats.mode.pc.short"
        case .phone: "cheats.mode.phone.short"
        }
    }

    var symbolName: String {
        switch self {
        case .playstation, .xbox: "gamecontroller.fill"
        case .pc: "keyboard.fill"
        case .phone: "iphone.gen3"
        }
    }
}

extension CheatCategory {
    var label: LocalizedStringResource {
        switch self {
        case .player: "cheats.category.player"
        case .weapons: "cheats.category.weapons"
        case .vehicles: "cheats.category.vehicles"
        case .world: "cheats.category.world"
        case .misc: "cheats.category.misc"
        }
    }
}
```

Les deux familles de manette partagent `gamecontroller.fill` : aucun glyphe propriétaire, et le segmenté les distingue par son libellé.

- [ ] **Step 4: Réécrire la liste**

Remplacer `NeonCompass/Features/Cheats/CheatsListView.swift` :

```swift
import SwiftUI

struct CheatsListView: View {
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 12) {
                    inputModePicker
                    TextField("cheats.search.placeholder", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: .capsule)

                    ForEach(model.sections, id: \.category) { section in
                        sectionHeader(section.category)
                        ForEach(section.cheats) { cheat in
                            if let code = cheat.codes[model.activeInputMode] {
                                CheatCard(
                                    cheat: cheat,
                                    code: code,
                                    isFavorite: model.isFavorite(cheat),
                                    onTap: { onSelect(cheat) },
                                    onToggleFavorite: { model.toggleFavorite(cheat) }
                                )
                            }
                        }
                    }

                    if !model.unavailableInActiveMode.isEmpty {
                        CheatsUnavailableGroup(
                            cheats: model.unavailableInActiveMode,
                            model: model,
                            onSelect: onSelect
                        )
                    }

                    footnote
                }
                .padding(16)
                .padding(.bottom, proEntitlementModel.isProEntitled ? 0 : bannerClearance)
            }
            if !proEntitlementModel.isProEntitled {
                adBanner
            }
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private func sectionHeader(_ category: CheatCategory) -> some View {
        Text(category.label)
            .font(NCTypography.cardMeta)
            .foregroundStyle(NCColor.sunsetOrange)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    /// Quatre segments d'icônes : le mode se choisit une fois et se retient, il
    /// ne mérite pas plus de surface, mais il doit rester visible pour qu'on
    /// découvre qu'il y en a quatre.
    private var inputModePicker: some View {
        Picker("cheats.mode.picker", selection: $model.activeInputMode) {
            ForEach(CheatInputMode.allCases, id: \.self) { mode in
                Text(mode.shortLabel)
                    .tag(mode)
                    .accessibilityLabel(Text(mode.label))
            }
        }
        .pickerStyle(.segmented)
    }

    /// Une fois en pied de liste, pas trente-six fois sur les cartes : ce que
    /// l'utilisateur veut savoir des trophées, il veut le savoir une fois.
    private var footnote: some View {
        Text("cheats.footnote.safe")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }

    /// La réservation vient de `BannerAdView` lui-même, qui la définit à partir
    /// de la taille qu'il DEMANDE et qu'il clampe.
    private var bannerClearance: CGFloat {
        (sizeClass == .compact ? NCLayout.compactTabBarClearance : 0) + BannerAdView.reservedHeight
    }

    private var adBanner: some View {
        BannerAdView()
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
    }
}
```

Les libellés courts (`PS`, `Xbox`, `Clavier`, `Téléphone`) sont là pour que quatre segments tiennent en largeur compacte, et le nom complet reste ce que VoiceOver annonce. `symbolName` n'est délibérément pas utilisé par le segmenté : les deux familles de manette y partageraient le même symbole et deviendraient indistinguables. Il ne sert qu'aux boutons du groupe des codes indisponibles, où le libellé lève l'ambiguïté.

- [ ] **Step 5: Vérifier à l'œil, iPhone et iPad**

```bash
Scripts/build.sh
```

Puis lancer l'app et contrôler, sur iPhone 16 **et** sur iPad :
1. Les quatre segments tiennent sans troncature. Sinon, `.iconOnly`.
2. Une séquence longue (Buzzard, 12 boutons) ne sort pas de la carte.
3. Le groupe replié apparaît en mode manette et disparaît en mode téléphone.
4. Le bouton copier n'apparaît qu'en modes clavier et téléphone.

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Features/Cheats NeonCompass/Resources/Localizable.xcstrings
git commit -m "$(cat <<'EOF'
feat(cheats): la liste se lit par catégorie, et n'escamote aucun code

Trente-six codes à plat se scrollent mal, et quatorze d'entre eux sont
des apparitions de véhicules. Des sections par catégorie, favoris en tête
de chaque groupe.

Les huit codes qu'un joueur manette ne peut pas saisir ne sont plus
invisibles : un groupe replié en bas les nomme, et le tap emmène dans le
mode où ils existent au lieu de se contenter de l'annoncer.

Le badge « bloque les trophées » disparaît des cartes. Aucun code de
GTA V n'empêche le 100 % — il ne se serait jamais déclenché. L'inverse
est ce qu'on veut lire, et une fois suffit.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Bascule V/VI et état d'attente

**Files:**
- Modify: `NeonCompass/Features/Cheats/CheatsScreen.swift`
- Create: `NeonCompass/Features/Cheats/CheatsEmptyGameView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CheatsModel.activeGame` (tâche 6), `Game.shortLabel` (tâche 4).
- Produces: rien que d'autres tâches consomment.

- [ ] **Step 1: Ajouter les chaînes**

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `cheats.game.picker` | Game | Jeu | Juego | Gioco | Spiel |
| `cheats.empty.title` | No codes yet | Pas encore de codes | Aún no hay códigos | Ancora nessun codice | Noch keine Codes |
| `cheats.empty.body` | The game is out on 19 November 2026. Its codes will land here once players have found and confirmed them — we won't guess them in advance. | Le jeu sort le 19 novembre 2026. Ses codes arriveront ici dès que les joueurs les auront trouvés et confirmés — nous ne les devinerons pas d'avance. | El juego sale el 19 de noviembre de 2026. Sus códigos llegarán aquí cuando los jugadores los encuentren y confirmen: no los adivinaremos por adelantado. | Il gioco esce il 19 novembre 2026. I suoi codici arriveranno qui quando i giocatori li avranno trovati e confermati: non li indovineremo in anticipo. | Das Spiel erscheint am 19. November 2026. Seine Codes kommen hierher, sobald Spieler sie gefunden und bestätigt haben — wir raten sie nicht vorab. |

Le corps du texte dit pourquoi c'est vide, pas seulement que c'est vide. C'est la même ligne que tient le fil d'actu : pas de spéculation présentée comme un fait.

- [ ] **Step 2: Écrire l'état d'attente**

Créer `NeonCompass/Features/Cheats/CheatsEmptyGameView.swift` :

```swift
import SwiftUI

/// Ce que voit quelqu'un qui bascule sur un jeu dont aucun code n'existe
/// encore. Informatif, sans bouton de notification : le seul dispositif
/// d'abonnement de l'app est câblé sur les catégories de POI, et le
/// généraliser est un autre chantier.
struct CheatsEmptyGameView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(NCColor.neonCyan)
            Text("cheats.empty.title")
                .font(NCTypography.cardTitle)
                .foregroundStyle(.white)
            Text("cheats.empty.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NCColor.nightSky.ignoresSafeArea())
    }
}
```

- [ ] **Step 3: Câbler l'écran**

Remplacer `NeonCompass/Features/Cheats/CheatsScreen.swift` :

```swift
import SwiftUI
import SwiftData

struct CheatsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSummaryCoordinator.self) private var widgetSummaryCoordinator
    @State private var model: CheatsModel?
    @State private var readerCheat: Cheat?

    // Guides reste hors de cet écran en attendant une refonte de la bascule
    // Codes/Guides (le Picker segmenté n'était pas la bonne UX pour arbitrer
    // deux types de contenu). GuidesModel/GuidesListView/GuideDetailView/
    // Guide.swift sont intacts et prêts à être rebranchés.
    //
    // Le segmenté qui revient ici porte sur autre chose : le mode de saisie
    // est une loupe sur une même liste, pas une navigation entre deux
    // contenus.

    var body: some View {
        Group {
            if let model {
                cheatsContent(model: model)
            } else {
                ProgressView()
            }
        }
        // Cf. FeedScreen : accrochée au ProgressView, cette tâche s'annulait
        // elle-même dès que `model` était assigné, et `updateCheats` n'était
        // jamais atteint.
        .task { await loadCheatsModel() }
    }

    @ViewBuilder
    private func cheatsContent(model: CheatsModel) -> some View {
        Group {
            if model.sections.isEmpty && model.unavailableInActiveMode.isEmpty
                && model.searchQuery.isEmpty {
                CheatsEmptyGameView()
            } else {
                CheatsListView(model: model) { cheat in
                    readerCheat = cheat
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                gamePicker(model: model)
            }
        }
        .fullScreenCover(item: $readerCheat) { cheat in
            let readable = model.sections.flatMap(\.cheats)
            if let index = readable.firstIndex(where: { $0.id == cheat.id }) {
                CheatReaderView(
                    cheats: readable,
                    startIndex: index,
                    inputMode: model.activeInputMode,
                    onDismiss: { readerCheat = nil }
                )
            }
        }
    }

    /// Le jeu est un changement de contexte — tout le contenu change — donc il
    /// vit dans le chrome, pas dans la liste. Deux segments, l'étiquette courte
    /// que le fil d'actu utilise déjà.
    private func gamePicker(model: CheatsModel) -> some View {
        Picker("cheats.game.picker", selection: Binding(
            get: { model.activeGame },
            set: { model.activeGame = $0 }
        )) {
            // Ordre explicite, pas `allCases` : l'énumération déclare `leonida`
            // en premier et le sélecteur afficherait « VI | V ».
            ForEach([Game.reference, .leonida], id: \.self) { game in
                Text(game.shortLabel).tag(game)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private func loadCheatsModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<Cheat>.live(
            collectionName: "cheats",
            seed: CheatLoader.bundled,
            modelContext: modelContext
        )
        model = CheatsModel(
            cheats: contentStore.items,
            modelContext: modelContext,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )
        try? await contentStore.syncIfNeeded()
        model?.updateCheats(contentStore.items)
    }
}
```

La condition de l'état d'attente inclut `searchQuery.isEmpty` : une recherche sans résultat n'est pas un jeu sans codes, et afficher « pas encore de codes » là serait un mensonge.

- [ ] **Step 4: Vérifier**

```bash
Scripts/build.sh
```

Puis, dans l'app : basculer sur `VI` doit montrer l'état d'attente ; revenir sur `V` doit retrouver la liste et le mode de saisie précédemment choisi. Fermer et relancer l'app : le jeu **et** le mode doivent être ceux qu'on avait laissés.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Cheats NeonCompass/Resources/Localizable.xcstrings
git commit -m "$(cat <<'EOF'
feat(cheats): la bascule entre les deux jeux, et ce qu'on dit du vide

Le jeu change tout le contenu : il va dans la toolbar, pas dans la
liste. Le mode de saisie, qui n'est qu'une loupe sur une même liste,
reste sous la recherche. Deux contrôles de même apparence pour des
portées si différentes se confondraient.

L'état d'attente de GTA VI dit pourquoi c'est vide, pas seulement que
c'est vide : les codes viendront quand des joueurs les auront confirmés,
et nous ne les devinerons pas d'avance. Sans bouton de notification —
l'abonnement de l'app est câblé sur les catégories de POI, le
généraliser est un autre chantier.

Une recherche sans résultat n'active pas cet état : ce serait un
mensonge.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Le lecteur plein écran

**Files:**
- Modify: `NeonCompass/Features/Cheats/CheatReaderView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CheatCodeView` (tâche 7), `CheatInputMode` (tâche 4).
- Produces: `CheatReaderView(cheats:startIndex:inputMode:onDismiss:)` — appelé par la tâche 9.

- [ ] **Step 1: Réécrire le lecteur**

Remplacer `NeonCompass/Features/Cheats/CheatReaderView.swift` :

```swift
import SwiftUI

/// Le mode « manette en main » : un seul code, aussi gros que possible, et
/// l'écran qui ne s'éteint pas pendant qu'on le saisit.
struct CheatReaderView: View {
    let cheats: [Cheat]
    let inputMode: CheatInputMode
    let onDismiss: () -> Void

    @State private var currentIndex: Int

    init(cheats: [Cheat], startIndex: Int, inputMode: CheatInputMode, onDismiss: @escaping () -> Void) {
        self.cheats = cheats
        self.inputMode = inputMode
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: startIndex)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Text(cheats[currentIndex].effect.resolved(for: currentLanguageCode))
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let code = cheats[currentIndex].codes[inputMode] {
                    CheatCodeView(code: code, glyphSize: 56)
                        .frame(maxWidth: .infinity)
                }

                Button("cheats.reader.close", action: onDismiss)
                    .buttonStyle(.glassProminent)
                    .tint(NCColor.sunsetMagenta)
            }
            .padding(32)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < 0, currentIndex < cheats.count - 1 {
                        currentIndex += 1
                    } else if value.translation.width > 0, currentIndex > 0 {
                        currentIndex -= 1
                    }
                }
        )
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
```

Le `DragGesture` reste tel quel. Il mériterait un `TabView` paginé — il n'a ni suivi du doigt, ni rebond en butée, ni indicateur de position, et il intercepte les balayages d'accessibilité — mais c'est un défaut préexistant, indépendant des quatre modes de saisie. Le corriger ici serait un refactor d'opportunité ; il part dans le rapport de fin comme suite à donner.

`UIApplication.shared.isIdleTimerDisabled` était déjà là et reste : c'est le second point où UIKit entre, et il n'a pas d'équivalent SwiftUI. Le laisser sur place plutôt que de le déplacer dans `Core/System/` — un type pour deux lignes utilisées à un seul endroit coûterait plus qu'il ne rapporte.

- [ ] **Step 2: Vérifier**

```bash
Scripts/build.sh
```

Dans l'app : ouvrir un code, balayer d'un code à l'autre, vérifier que les glyphes tiennent à la taille 56 pour une séquence de douze boutons (Buzzard), que le mot-clé et le numéro s'affichent bien en gros, et que le bouton copier reste atteignable. Si douze glyphes à 56 pt débordent malgré l'enveloppement de `CheatCodeView`, réduire à 44 pt plutôt que de tronquer : un code coupé ne sert à rien.

- [ ] **Step 3: Lancer toute la suite**

```bash
Scripts/test.sh
cd tools/content-cli && npm test
```

Attendu : tout vert des deux côtés.

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatReaderView.swift
git commit -m "$(cat <<'EOF'
feat(cheats): le lecteur plein écran montre les trois formes de code

Il ne savait afficher qu'une rangée de glyphes. Il partage désormais la
vue de rendu avec la carte et ne diffère que par la taille.

Le DragGesture maison reste en place, avec ses défauts — pas de suivi du
doigt, pas de rebond en butée, pas d'indicateur de position, et il
intercepte les balayages d'accessibilité. C'est antérieur aux quatre
modes de saisie et ça se corrige à part.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Revue du plan contre le spec

| Exigence du spec | Tâche |
|---|---|
| D1 — `codes`, dictionnaire de modes à charge typée | 1, 4 |
| D2 — `game` sur la triche, dans l'identifiant, `Game` partagé | 1, 3, 4 |
| D3 — jeu en toolbar, mode de saisie en segmenté | 8, 9 |
| D4 — codes absents du mode actif visibles, pas masqués | 6, 8 |
| D5 — saisie immédiate : sections, favoris, copie, lecteur | 7, 8, 10 |
| D6 — `blocksTrophies` inversé en réassurance, affichée une fois | 8 |
| D7 — noms de véhicules gardés, effets réécrits, EN + FR, `draft` | 3 |
| D8 — `lb/lt/rb/rt`, `Platform` → `CheatInputMode`, clé migrée | 4, 6 |
| D9 — socle embarqué, `check-seeds`, `project.yml`, deux sites `.live` | 5 |
| Lacune PlayStation de la visée au ralenti à recouper | 3, étape 1 |
| Hors périmètre : notification VI, es/it/de, codes VI | 9 (état d'attente sans bouton) |
| Tests : décodage, round-trip, migration, partition, validation contenu | 4, 5, 6 |

**Ce que le plan ajoute au spec, assumé :**

- **Recoupement des 36 codes sur une seconde source, et publication** (tâche 3, étape 1). Le spec prévoyait `status: draft` et une seule source. Mais `check-publishable` exige deux sources pour publier un cheat, et le socle de D9 embarque indépendamment du statut : le binaire aurait transporté ce que la porte de publication refuse. Recouper est moins coûteux que d'assumer cette incohérence, et ça règle au passage la lacune de la visée au ralenti.
- **Retrait du badge `blocksTrophies` de la carte** (tâche 8). D6 demandait de déplacer l'information en pied d'écran ; retirer le badge en est la conséquence, pas une décision séparée.
- **`CaseIterable` sur `GamepadButton`** (tâche 4), pour que le test des glyphes puisse parcourir tous les boutons — c'est ce test qui aurait attrapé le bug `lb`.
- **Libellés courts distincts pour le segmenté** (tâche 8), parce que quatre segments dont l'un dit « Manette PlayStation » tronquent tout le reste en largeur compacte.

**Ce que le plan ne fait pas** : aucune bascule FR-primaire, aucun ajout au registre de sources, aucune généralisation du notifieur, aucun code GTA VI, aucun `es`/`it`/`de` dans `content/` (les chaînes d'interface, elles, sont bien traduites dans les 5 langues, comme l'exige la contrainte globale).
