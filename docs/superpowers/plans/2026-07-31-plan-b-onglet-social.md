# Plan B — Onglet Social Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poser l'onglet Social sur l'emplacement libéré par le plan A : les événements Online de la semaine (B1), puis le classement des contributeurs (B2).

**Architecture:** B1 est entièrement autonome du serveur — un nouveau type de contenu passe par le pipeline existant (`content/schema` → CLI → CDN/Firestore → `ContentStore`), et le rappel est une notification **locale** programmée sur `endsAt`. B2 ajoute une Cloud Function planifiée qui agrège le classement dans **un seul document**, jamais une requête client sur la collection des profils.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, SwiftData, Swift Testing, Node ESM (`tools/content-cli`, ajv), TypeScript (`functions/`, Firebase Functions v2).

**Spec:** `docs/superpowers/specs/2026-07-31-onglet-social-design.md`
**Prérequis :** plan A livré (`docs/superpowers/plans/2026-07-31-plan-a-profil-complet.md`) — il libère l'emplacement d'onglet.

## Global Constraints

- **iOS 26 minimum**, iPhone + iPad. **Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`.**
- **Tests en Swift Testing** côté app, `node --test` côté CLI, le harnais existant côté Functions.
- **Aucune chaîne littérale visible** : tout passe par `Localizable.xcstrings`, et `LocalizationCoverageTests` exige les cinq locales `en, fr, es, it, de` non vides pour chaque clé. Format Xcode : indentation 2 espaces, `"clé" : valeur` avec un espace avant **et** après le deux-points. `tools/xcstrings-locale/apply-locale.js` ne sert pas ici — il exige des traductions pour la totalité du catalogue.
- **Interpolation et clés de catalogue.** `Text("clé \(n)")` ne cherche PAS `clé` : SwiftUI construit la clé `clé %lld`, spécificateur compris. La clé du catalogue doit donc le porter (`progress.challenge.foundCount %lld` est le précédent), et le littéral Swift ne le porte jamais. Trois clés du projet ont déjà livré ce défaut, dont deux visibles en production ; `LocalizationCoverageTests.interpolatedCallSitesResolveToACatalogKey` l'attrape désormais. Corollaire : un nombre nu sans phrase autour (`Text("\(n)")`) doit passer par `Text(verbatim:)`, sinon il devient une souche vide dans le catalogue.
- **Les souches `%@` de l'extracteur, à supprimer avant chaque commit.** Compiler un `Text("clé \(n)")` neuf fait ajouter par Xcode une entrée `clé %@` SANS aucune localisation, qui fait échouer `everyKeyHasAllFiveLocales`. Elle est toujours fausse : pour un `Int`, SwiftUI cherche `clé %lld` à l'exécution — Xcode marque d'ailleurs les entrées `%lld` correctes comme `"extractionState" : "stale"`, c'est un désaccord connu entre son extracteur et l'interpolation SwiftUI, et c'est l'extracteur qui a tort. Après le build, vérifier le catalogue et retirer toute entrée dépourvue de bloc `localizations`. Elles reviennent à chaque build : les supprimer une fois ne suffit pas.
- **Marques déposées interdites** dans toute chaîne d'interface. Les jeux se nomment par leurs chiffres romains (`Game.shortLabel`).
- **`sources` n'est jamais embarqué dans le modèle Swift** : les URL contiennent les marques (`gtaboom.com/rockstar-…`). Même règle que `NewsItem`, dont le commentaire l'explique — elles reviendront avec la bascule de marques.
- **Sources autorisées uniquement** : GTABOOM, Leonidaverse, GTA6.gg. `rockstargames.com` est interdit à la veille automatique (`robots.txt : ClaudeBot Disallow: /`). `tools/content-cli/source-policy.mjs` fait autorité et lève sur un domaine interdit.
- **`xcodegen generate` après toute création de fichier source.** `project.yml` n'a jamais à être modifié (il glob `NeonCompass/`), mais sans régénération le `.xcodeproj` ignore le fichier — et `xcodebuild` rapporte alors silencieusement « 0 tests » **au lieu d'un échec de compilation**. C'est le piège qui vide l'étape « vérifier que le test échoue » de tout son sens : on croit voir un échec TDD là où rien n'a été compilé.
- **Jamais de `ToolbarItem` dans un écran d'onglet** : aucun n'a de `NavigationStack`, `RootView` les empile dans un `ZStack` sous une barre maison, et l'item ne s'afficherait nulle part sans erreur.
- **Firebase reste derrière un protocole dans `Core/`.**

**Commandes :**

```sh
# App
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test

# CLI de contenu
cd tools/content-cli && node --test

# Cloud Functions
cd functions && npm test
```

## Structure des fichiers

**Palier B1 — les événements**

| Fichier | Responsabilité | État |
|---|---|---|
| `content/schema/online-event.schema.json` | Le contrat de données | **Créé** (T1) |
| `tools/content-cli/cli.js:56-75` | Le kind `online-events` | **Modifié** (T1) |
| `tools/content-cli/facts-to-online-event.mjs` | Fait d'inbox → événement | **Créé** (T2) |
| `tools/content-cli/facts-to-online-event.test.mjs` | Sa couverture | **Créé** (T2) |
| `NeonCompass/Core/Online/OnlineEvent.swift` | Le modèle + la fenêtre temporelle | **Créé** (T3) |
| `NeonCompassTests/Online/OnlineEventTests.swift` | Sa couverture | **Créé** (T3) |
| `NeonCompass/Features/Social/OnlineEventsModel.swift` | Événement courant, sélecteur de jeu | **Créé** (T4) |
| `NeonCompassTests/Social/OnlineEventsModelTests.swift` | Sa couverture | **Créé** (T4) |
| `NeonCompass/Features/Social/SocialScreen.swift` | L'écran | **Créé** (T5) |
| `NeonCompass/Features/Social/OnlineEventCard.swift` | La carte de la semaine | **Créé** (T5) |
| `NeonCompass/App/AppTab.swift` | `.social` | **Modifié** (T5) |
| `NeonCompass/App/RootView.swift` | `screen(for:)` | **Modifié** (T5) |
| `NeonCompass/Core/Notifications/LocalNotificationScheduling.swift` | Le protocole + son implémentation | **Créé** (T6) |
| `NeonCompass/Core/Online/EventReminderScheduler.swift` | Quoi programmer, quand | **Créé** (T6) |
| `NeonCompassTests/Online/EventReminderSchedulerTests.swift` | Sa couverture | **Créé** (T6) |
| `firestore.rules` | Lecture publique de `online_events` | **Modifié** (T1) |

**Palier B2 — le classement**

| Fichier | Responsabilité | État |
|---|---|---|
| `functions/src/leaderboard.ts` | Le calcul, pur, sans Firestore | **Créé** (T8) |
| `functions/src/leaderboard.test.ts` | Sa couverture | **Créé** (T8) |
| `functions/src/rebuildLeaderboard.ts` | La Function planifiée | **Créé** (T8) |
| `functions/src/index.ts` | Son export | **Modifié** (T8) |
| `NeonCompass/Core/Community/Leaderboard.swift` | Le modèle + le protocole de dépôt | **Créé** (T9) |
| `NeonCompass/Core/Community/FirestoreLeaderboardRepository.swift` | Sa lecture réelle, une par ouverture d'onglet | **Créé** (T9) |
| `NeonCompass/Features/Social/LeaderboardSection.swift` | La section | **Créé** (T9) |
| `NeonCompass/Features/Profile/ProfileHeaderView.swift` | Le rang personnel | **Modifié** (T9) |

---

# Palier B1 — Les événements de la semaine

### Task 1: Le schéma de contenu et son kind

**Files:**
- Create: `content/schema/online-event.schema.json`
- Create: `content/online-events/.gitkeep`
- Modify: `tools/content-cli/cli.js` (bloc `compiled` ~ligne 56, bloc `KINDS` ~ligne 70)
- Modify: `firestore.rules`

**Interfaces:**
- Consumes: rien.
- Produces: le kind `online-events` → collection Firestore `online_events`, schéma `online-event.schema.json`.

**Décision de format à ne pas confondre avec `news`.** `news.schema.json` impose une date **courte sans horodatage** parce que `FeedModel` trie par comparaison de chaînes. Ici c'est l'inverse : un compte à rebours a besoin d'une heure. `startsAt`/`endsAt` sont donc des **horodatages ISO 8601 en UTC**. C'est la divergence assumée qui justifie un schéma séparé.

- [ ] **Step 1: Écrire le schéma**

Créer `content/schema/online-event.schema.json` :

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "online-event.schema.json",
  "title": "Neon Compass Online Event",
  "type": "object",
  "required": ["id", "game", "startsAt", "endsAt", "title", "status", "sources", "confidence"],
  "additionalProperties": false,
  "properties": {
    "id": { "type": "string", "pattern": "^online_[a-z0-9_]+$" },
    "game": {
      "enum": ["leonida", "gtav"],
      "description": "Même vocabulaire que Game (NeonCompass/Core/Game.swift). L'onglet démarre sur `gtav` : son mode en ligne tourne, celui de Leonida n'est pas ouvert."
    },
    "startsAt": {
      "type": "string",
      "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$",
      "description": "Horodatage UTC complet, PAS une date courte comme news.publishedAt. Un compte à rebours a besoin d'une heure ; c'est la raison d'être d'un schéma séparé."
    },
    "endsAt": {
      "type": "string",
      "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$",
      "description": "Fin de la fenêtre. C'est LUI qui gouverne l'affichage et le rappel local — jamais un calcul de jour de semaine, la cadence de Leonida étant inconnue."
    },
    "title": { "$ref": "#/$defs/localized" },
    "bonuses": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["activity", "label"],
        "additionalProperties": false,
        "properties": {
          "activity": { "$ref": "#/$defs/localized" },
          "label": { "$ref": "#/$defs/localized" }
        }
      }
    },
    "discounts": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["item", "percent"],
        "additionalProperties": false,
        "properties": {
          "item": { "$ref": "#/$defs/localized" },
          "percent": { "type": "integer", "minimum": 1, "maximum": 100 }
        }
      }
    },
    "podiumVehicle": { "$ref": "#/$defs/localized" },
    "status": { "enum": ["draft", "published"] },
    "sources": { "type": "array", "minItems": 1, "items": { "type": "string" } },
    "confidence": {
      "enum": ["confirmed-official", "multi-source", "single-source", "rumor"],
      "description": "Identique à news : check-publishable refuse déjà de publier une rumeur."
    },
    "processedFrom": {
      "type": "string",
      "description": "Clé d'identité du fait d'origine — ce qui rend le run idempotent."
    },
    "sourceClaim": {
      "type": "string",
      "description": "Le fait brut, conservé pour la relecture. Jamais affiché : il cite ses sources mot pour mot, marques comprises."
    },
    "needsRewrite": {
      "type": "boolean",
      "description": "Squelette posé par le run, pas encore rédigé. check-publishable refuse de le publier tant que le drapeau est là."
    }
  },
  "$defs": {
    "localized": {
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
    }
  }
}
```

Créer le répertoire :

```sh
mkdir -p content/online-events && touch content/online-events/.gitkeep
```

- [ ] **Step 2: Déclarer le kind dans le CLI**

Dans `tools/content-cli/cli.js`, ajouter au bloc de compilation des schémas (à la suite de la ligne `news:`) :

```js
  'online-events': ajv.compile(JSON.parse(readFileSync(join(CONTENT, 'schema', 'online-event.schema.json'), 'utf8'))),
```

Et au bloc `KINDS` :

```js
  'online-events': { schema: 'online-events', collection: 'online_events' },
```

Le garde-fou `needsRewrite` doit s'appliquer au nouveau kind comme à `news`. Localiser la ligne existante (~121) et l'étendre :

```js
    if ((kind === 'news' || kind === 'online-events') && data.status === 'published' && data.needsRewrite) {
```

- [ ] **Step 3: Ouvrir la lecture dans les règles Firestore**

Dans `firestore.rules`, à côté du bloc `match /news/{document=**}` :

```
    match /online_events/{document=**} {
      allow read: if true;
      allow write: if false;
    }
```

Lecture publique, comme tout le contenu éditorial : l'onglet Social se consulte sans compte. Écriture toujours refusée — le contenu passe par le CLI d'admin, jamais par un client.

- [ ] **Step 4: Vérifier la validation**

Écrire une fixture volontairement invalide et vérifier que le CLI la refuse :

```sh
cat > /tmp/bad-event.json <<'JSON'
{"id":"online_bad","game":"gtav","startsAt":"2026-08-06","endsAt":"2026-08-13T09:00:00Z",
 "title":{"en":"x"},"status":"draft","sources":["https://gtaboom.com/x"],"confidence":"multi-source"}
JSON
cp /tmp/bad-event.json content/online-events/
cd tools/content-cli && node cli.js validate
```

Attendu : échec, message pointant `/startsAt` (date courte au lieu d'un horodatage).

```sh
rm ../../content/online-events/bad-event.json
```

- [ ] **Step 5: Commit**

```bash
git add content/schema/online-event.schema.json content/online-events/.gitkeep \
        tools/content-cli/cli.js firestore.rules
git commit -m "feat(contenu): un schéma d'événement en ligne, distinct de l'actu

Une entrée d'actu vit sur sa publishedAt — d'où la date courte, que FeedModel
trie par comparaison de chaînes. Un événement vit sur son endsAt, et un compte
à rebours a besoin d'une heure : startsAt/endsAt sont des horodatages UTC
complets. C'est cette divergence qui justifie un schéma séparé plutôt qu'une
extension de news."
```

---

### Task 2: La transformation fait d'inbox → événement

**Files:**
- Create: `tools/content-cli/facts-to-online-event.mjs`
- Create: `tools/content-cli/facts-to-online-event.test.mjs`

**Interfaces:**
- Consumes: le schéma (T1), le format de fait d'inbox lu par `facts-to-news.mjs`.
- Produces: `export function factToOnlineEvent(fact) → object` et `export function identityKey(fact) → string`.

Pas de paramètre `now` : le schéma est en `additionalProperties: false`, donc aucun champ d'horodatage de génération n'y a sa place — et git porte déjà cette information.

Lire `tools/content-cli/facts-to-news.mjs` **avant d'écrire** : la forme du fait d'inbox, le hachage d'identité et l'idempotence par `processedFrom` s'en reprennent à l'identique. Ne pas réinventer un second format.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `tools/content-cli/facts-to-online-event.test.mjs` :

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { factToOnlineEvent, identityKey } from './facts-to-online-event.mjs';

const FACT = {
  kind: 'online-event',
  claim: 'Double GTA$ on sea races until August 13.',
  sources: ['https://gtaboom.com/weekly-update'],
  confidence: 'multi-source',
  game: 'gtav',
  startsAt: '2026-08-06T09:00:00Z',
  endsAt: '2026-08-13T09:00:00Z',
};

test('un squelette est produit, marqué à rédiger', () => {
  const event = factToOnlineEvent(FACT);
  assert.equal(event.status, 'draft');
  assert.equal(event.needsRewrite, true);
  assert.equal(event.game, 'gtav');
  assert.equal(event.endsAt, '2026-08-13T09:00:00Z');
});

test("l'identité est stable pour un même fait", () => {
  assert.equal(identityKey(FACT), identityKey({ ...FACT }));
  assert.equal(factToOnlineEvent(FACT).processedFrom, identityKey(FACT));
});

test("l'identité change si le fait change", () => {
  assert.notEqual(identityKey(FACT), identityKey({ ...FACT, claim: 'autre chose' }));
});

test("l'identifiant respecte le motif du schéma", () => {
  const event = factToOnlineEvent(FACT);
  assert.match(event.id, /^online_[a-z0-9_]+$/);
});

test('le fait brut est conservé pour la relecture, jamais comme titre', () => {
  const event = factToOnlineEvent(FACT);
  assert.equal(event.sourceClaim, FACT.claim);
  assert.notEqual(event.title.en, FACT.claim);
});

test('un fait sans fenêtre est refusé — sans endsAt il n’y a pas de compte à rebours', () => {
  const { endsAt, ...sansFin } = FACT;
  assert.throws(() => factToOnlineEvent(sansFin), /endsAt/);
});

/// Le schéma est en additionalProperties:false : tout champ hors contrat fait
/// échouer la validation du CLI, pas la transformation — d'où ce test ici.
test('aucun champ hors schéma n’est produit', () => {
  const permis = new Set(['id', 'game', 'startsAt', 'endsAt', 'title', 'bonuses', 'discounts',
    'podiumVehicle', 'status', 'sources', 'confidence', 'processedFrom', 'sourceClaim', 'needsRewrite']);
  for (const key of Object.keys(factToOnlineEvent(FACT))) {
    assert.ok(permis.has(key), `champ hors schéma : ${key}`);
  }
});
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

```sh
cd tools/content-cli && node --test facts-to-online-event.test.mjs
```

Attendu : `Cannot find module './facts-to-online-event.mjs'`.

- [ ] **Step 3: Écrire la transformation**

Créer `tools/content-cli/facts-to-online-event.mjs` :

```js
import { createHash } from 'node:crypto';

/// Identité stable par hachage du CONTENU du fait, pas de sa position dans
/// l'inbox : c'est ce qui rend le run idempotent. Un fait déjà transformé se
/// réapparie sur son événement au lieu d'en créer un second.
export function identityKey(fact) {
  const material = [fact.claim, fact.game, fact.startsAt, fact.endsAt, ...(fact.sources ?? [])].join(' ');
  return createHash('sha256').update(material).digest('hex').slice(0, 16);
}

export function factToOnlineEvent(fact) {
  if (!fact.endsAt) {
    throw new Error('endsAt manquant : sans fenêtre de fin, il n’y a pas de compte à rebours à afficher');
  }
  if (!fact.startsAt) {
    throw new Error('startsAt manquant');
  }
  const key = identityKey(fact);
  return {
    id: `online_${fact.game}_${key}`,
    game: fact.game,
    startsAt: fact.startsAt,
    endsAt: fact.endsAt,
    // Squelette : le titre est une étiquette neutre, jamais la revendication
    // de la source — elle cite ses marques mot pour mot.
    title: { en: `Weekly update — ${fact.startsAt.slice(0, 10)}` },
    bonuses: [],
    discounts: [],
    status: 'draft',
    sources: fact.sources ?? [],
    confidence: fact.confidence,
    processedFrom: key,
    sourceClaim: fact.claim,
    needsRewrite: true,
  };
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

```sh
cd tools/content-cli && node --test facts-to-online-event.test.mjs
```

Attendu : 7 tests au vert.

- [ ] **Step 5: Étendre le contrôle d'originalité**

`check-originality.mjs` doit couvrir le nouveau kind : une liste de remises nomme des véhicules et des commerces, et rien ne doit passer sans contrôle. Lire le fichier, repérer la liste de kinds qu'il parcourt, y ajouter `online-events`, et vérifier qu'il inspecte `title`, `bonuses[].activity`, `bonuses[].label`, `discounts[].item` et `podiumVehicle` — **pas** `sourceClaim`, qui a le droit de citer ses sources mot pour mot.

- [ ] **Step 6: Lancer toute la suite du CLI**

```sh
cd tools/content-cli && node --test
```

Attendu : tout au vert, y compris les suites existantes.

- [ ] **Step 7: Commit**

```bash
git add tools/content-cli/facts-to-online-event.mjs \
        tools/content-cli/facts-to-online-event.test.mjs \
        tools/content-cli/check-originality.mjs
git commit -m "feat(contenu): les faits d'inbox deviennent des événements en ligne

Même identité par hachage du contenu et même idempotence par processedFrom
que facts-to-news : un fait déjà transformé se réapparie au lieu de se
dupliquer.

Un fait sans endsAt est refusé : sans fenêtre de fin il n'y a pas de compte à
rebours, et c'est le compte à rebours qui fait l'intérêt de l'onglet.

check-originality couvre le nouveau kind — une liste de remises nomme des
véhicules et des commerces."
```

---

### Task 3: Le modèle Swift et sa fenêtre temporelle

**Files:**
- Create: `NeonCompass/Core/Online/OnlineEvent.swift`
- Create: `NeonCompassTests/Online/OnlineEventTests.swift`

**Interfaces:**
- Consumes: `Game`, `LocalizedText`, `ContentItem`.
- Produces:
  - `struct OnlineEventBonus: Codable, Equatable, Sendable { let activity: LocalizedText; let label: LocalizedText }`
  - `struct OnlineEventDiscount: Codable, Equatable, Sendable { let item: LocalizedText; let percent: Int }`
  - `struct OnlineEvent: ContentItem, Equatable` avec `id, game, startsAt: Date, endsAt: Date, title, bonuses, discounts, podiumVehicle: LocalizedText?`
  - `func isActive(at now: Date) -> Bool`, `func remaining(at now: Date) -> TimeInterval?`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `NeonCompassTests/Online/OnlineEventTests.swift` :

```swift
import Testing
import Foundation
@testable import NeonCompass

struct OnlineEventTests {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func json(startsAt: String = "2026-08-06T09:00:00Z", endsAt: String = "2026-08-13T09:00:00Z") -> Data {
        Data("""
        {
          "id": "online_gtav_abc123",
          "game": "gtav",
          "startsAt": "\(startsAt)",
          "endsAt": "\(endsAt)",
          "title": { "en": "Weekly update", "fr": "Mise à jour de la semaine" },
          "bonuses": [{ "activity": { "en": "Sea races" }, "label": { "en": "Double payouts" } }],
          "discounts": [{ "item": { "en": "Speedboat" }, "percent": 30 }],
          "podiumVehicle": { "en": "Coupé" },
          "status": "published",
          "sources": ["https://example.test/x"],
          "confidence": "multi-source"
        }
        """.utf8)
    }

    @Test func decodesEveryField() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.id == "online_gtav_abc123")
        #expect(event.game == .reference)
        #expect(event.endsAt == date("2026-08-13T09:00:00Z"))
        #expect(event.bonuses.count == 1)
        #expect(event.discounts.first?.percent == 30)
        #expect(event.podiumVehicle?.resolved(for: "en") == "Coupé")
    }

    /// `sources` et `status` sont pipeline-only : Codable ignore les clés
    /// inconnues, et les URL contiennent les marques — les embarquer mettrait à
    /// l'écran exactement ce que la politique stricte évite.
    @Test func decodingIgnoresPipelineOnlyFields() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.title.resolved(for: "fr") == "Mise à jour de la semaine")
    }

    /// Les listes absentes valent liste vide, jamais un échec de décodage : le
    /// schéma ne les exige pas.
    @Test func absentListsDecodeAsEmpty() throws {
        let minimal = Data("""
        {
          "id": "online_gtav_min",
          "game": "gtav",
          "startsAt": "2026-08-06T09:00:00Z",
          "endsAt": "2026-08-13T09:00:00Z",
          "title": { "en": "Minimal" },
          "status": "published",
          "sources": ["https://example.test/x"],
          "confidence": "multi-source"
        }
        """.utf8)
        let event = try JSONDecoder().decode(OnlineEvent.self, from: minimal)
        #expect(event.bonuses.isEmpty)
        #expect(event.discounts.isEmpty)
        #expect(event.podiumVehicle == nil)
    }

    @Test func isActiveInsideTheWindow() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.isActive(at: date("2026-08-10T00:00:00Z")))
    }

    @Test func isNotActiveBeforeOrAfter() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(!event.isActive(at: date("2026-08-05T00:00:00Z")))
        #expect(!event.isActive(at: date("2026-08-14T00:00:00Z")))
    }

    /// La borne de fin est exclusive : à `endsAt` pile, c'est terminé.
    @Test func endBoundIsExclusive() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(!event.isActive(at: date("2026-08-13T09:00:00Z")))
    }

    @Test func remainingIsTheDistanceToTheEnd() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.remaining(at: date("2026-08-12T09:00:00Z")) == 86_400)
    }

    /// JAMAIS un compte à rebours négatif : un événement terminé rend nil, et
    /// la vue affiche « terminé » au lieu de « il reste -3 jours ».
    @Test func remainingIsNilOnceOver() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.remaining(at: date("2026-08-14T00:00:00Z")) == nil)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/OnlineEventTests
```

Attendu : `cannot find 'OnlineEvent' in scope`.

- [ ] **Step 3: Écrire le modèle**

Créer `NeonCompass/Core/Online/OnlineEvent.swift` :

```swift
import Foundation

struct OnlineEventBonus: Codable, Equatable, Sendable {
    let activity: LocalizedText
    let label: LocalizedText
}

struct OnlineEventDiscount: Codable, Equatable, Sendable {
    let item: LocalizedText
    let percent: Int
}

/// Une fenêtre de bonus et de remises du mode en ligne.
///
/// Distinct de `NewsItem`, et pas par goût de la symétrie : une entrée d'actu
/// vit sur sa date de publication, celle-ci vit sur sa date de FIN. C'est
/// `endsAt` qui gouverne l'affichage et le rappel — jamais un calcul de jour de
/// semaine, la cadence du mode en ligne à venir étant inconnue.
///
/// `status`, `sources`, `processedFrom`, `sourceClaim` et `needsRewrite` sont
/// absents : Codable ignore les clés inconnues, et les URL de sources
/// contiennent les marques. Même règle que `NewsItem`.
struct OnlineEvent: ContentItem, Equatable {
    let id: String
    let game: Game
    let startsAt: Date
    let endsAt: Date
    let title: LocalizedText
    let bonuses: [OnlineEventBonus]
    let discounts: [OnlineEventDiscount]
    let podiumVehicle: LocalizedText?

    private enum CodingKeys: String, CodingKey {
        case id, game, startsAt, endsAt, title, bonuses, discounts, podiumVehicle
    }

    /// Une fonction et non une `static let` : `ISO8601DateFormatter` n'est pas
    /// `Sendable`, et sous concurrence stricte une constante statique non
    /// isolée est refusée à la compilation.
    private static func formatter() -> ISO8601DateFormatter { ISO8601DateFormatter() }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        game = try container.decode(Game.self, forKey: .game)
        title = try container.decode(LocalizedText.self, forKey: .title)
        // Décodage strict des deux dates : un horodatage illisible rendrait
        // l'événement inaffichable de toute façon, et un repli silencieux
        // (« maintenant », « jamais ») produirait un compte à rebours faux —
        // pire qu'une absence.
        let startsRaw = try container.decode(String.self, forKey: .startsAt)
        let endsRaw = try container.decode(String.self, forKey: .endsAt)
        let formatter = Self.formatter()
        guard let starts = formatter.date(from: startsRaw),
              let ends = formatter.date(from: endsRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .endsAt,
                in: container,
                debugDescription: "Horodatage ISO 8601 attendu, reçu « \(startsRaw) » / « \(endsRaw) »"
            )
        }
        startsAt = starts
        endsAt = ends
        // Listes optionnelles au schéma : leur absence vaut vide, pas échec.
        bonuses = try container.decodeIfPresent([OnlineEventBonus].self, forKey: .bonuses) ?? []
        discounts = try container.decodeIfPresent([OnlineEventDiscount].self, forKey: .discounts) ?? []
        podiumVehicle = try container.decodeIfPresent(LocalizedText.self, forKey: .podiumVehicle)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let formatter = Self.formatter()
        try container.encode(id, forKey: .id)
        try container.encode(game, forKey: .game)
        try container.encode(formatter.string(from: startsAt), forKey: .startsAt)
        try container.encode(formatter.string(from: endsAt), forKey: .endsAt)
        try container.encode(title, forKey: .title)
        try container.encode(bonuses, forKey: .bonuses)
        try container.encode(discounts, forKey: .discounts)
        try container.encodeIfPresent(podiumVehicle, forKey: .podiumVehicle)
    }

    /// `now` est TOUJOURS passé, jamais lu depuis `Date()` : c'est la seule
    /// façon de tester une fenêtre temporelle.
    func isActive(at now: Date) -> Bool {
        now >= startsAt && now < endsAt
    }

    /// Secondes restantes, ou `nil` si c'est terminé. Jamais une valeur
    /// négative : la vue doit dire « terminé », pas « il reste -3 jours ».
    func remaining(at now: Date) -> TimeInterval? {
        let delta = endsAt.timeIntervalSince(now)
        return delta > 0 ? delta : nil
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/OnlineEventTests
```

Attendu : 8 tests au vert.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Online/OnlineEvent.swift NeonCompassTests/Online/OnlineEventTests.swift
git commit -m "feat(social): le modèle d'événement en ligne et sa fenêtre temporelle

now est toujours passé en paramètre, jamais lu depuis Date() : c'est la seule
façon de tester un compte à rebours.

remaining() rend nil une fois la fenêtre passée, jamais un négatif — la vue
doit dire « terminé », pas « il reste -3 jours »."
```

---

### Task 4: Le modèle d'écran

**Files:**
- Create: `NeonCompass/Features/Social/OnlineEventsModel.swift`
- Create: `NeonCompassTests/Social/OnlineEventsModelTests.swift`

**Interfaces:**
- Consumes: `OnlineEvent` (T3), `Game`, `ContentStore`.
- Produces: `@Observable @MainActor final class OnlineEventsModel` avec
  `init(events: [OnlineEvent], contentStore: ContentStore<OnlineEvent>? = nil)`,
  `var selectedGame: Game`,
  `var availableGames: [Game]`,
  `var showsGamePicker: Bool`,
  `func currentEvent(at now: Date) -> OnlineEvent?`,
  `func latestEvent() -> OnlineEvent?`,
  `func update(events: [OnlineEvent])`,
  `func refresh() async`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `NeonCompassTests/Social/OnlineEventsModelTests.swift` :

```swift
import Testing
import Foundation
@testable import NeonCompass

@MainActor
struct OnlineEventsModelTests {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func event(
        id: String,
        game: Game = .reference,
        startsAt: String,
        endsAt: String
    ) throws -> OnlineEvent {
        try JSONDecoder().decode(OnlineEvent.self, from: Data("""
        {
          "id": "\(id)", "game": "\(game.rawValue)",
          "startsAt": "\(startsAt)", "endsAt": "\(endsAt)",
          "title": { "en": "\(id)" }
        }
        """.utf8))
    }

    @Test func currentEventIsTheOneInsideTheWindow() throws {
        let past = try event(id: "online_a", startsAt: "2026-07-30T09:00:00Z", endsAt: "2026-08-06T09:00:00Z")
        let now = try event(id: "online_b", startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [past, now])
        #expect(model.currentEvent(at: date("2026-08-10T00:00:00Z"))?.id == "online_b")
    }

    /// Hors de toute fenêtre, il n'y a pas d'événement courant — la vue dira
    /// « terminé », elle ne montrera pas le dernier comme s'il durait encore.
    @Test func noCurrentEventOutsideEveryWindow() throws {
        let past = try event(id: "online_a", startsAt: "2026-07-30T09:00:00Z", endsAt: "2026-08-06T09:00:00Z")
        let model = OnlineEventsModel(events: [past])
        #expect(model.currentEvent(at: date("2026-08-10T00:00:00Z")) == nil)
        #expect(model.latestEvent()?.id == "online_a")
    }

    /// Le jeu sélectionné filtre : les bonus du volet en ligne actuel ne se
    /// mélangent pas à ceux du volet à venir.
    @Test func currentEventRespectsSelectedGame() throws {
        let five = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let six = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [five, six])
        model.selectedGame = .leonida
        #expect(model.currentEvent(at: date("2026-08-10T00:00:00Z"))?.id == "online_vi")
    }

    /// Même règle que `gamesWithChallenges` : pas de sélecteur tant qu'il n'y a
    /// rien à choisir. Tant que le mode en ligne à venir n'est pas ouvert, un
    /// sélecteur à une entrée ne ferait qu'occuper la place.
    @Test func gamePickerIsHiddenWithASingleGame() throws {
        let five = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [five])
        #expect(!model.showsGamePicker)
        #expect(model.availableGames == [.reference])
    }

    @Test func gamePickerAppearsWithBothGames() throws {
        let five = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let six = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [five, six])
        #expect(model.showsGamePicker)
        #expect(model.availableGames == [.leonida, .reference])
    }

    /// Le jeu par défaut est celui qui a du contenu : ouvrir sur un volet vide
    /// alors que l'autre a un événement en cours serait absurde.
    @Test func defaultGameIsOneThatHasEvents() throws {
        let six = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [six])
        #expect(model.selectedGame == .leonida)
    }

    @Test func emptyModelHasNothingAndCrashesNowhere() {
        let model = OnlineEventsModel(events: [])
        #expect(model.currentEvent(at: date("2026-08-10T00:00:00Z")) == nil)
        #expect(model.latestEvent() == nil)
        #expect(!model.showsGamePicker)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/OnlineEventsModelTests
```

Attendu : `cannot find 'OnlineEventsModel' in scope`.

- [ ] **Step 3: Écrire le modèle**

Créer `NeonCompass/Features/Social/OnlineEventsModel.swift` :

```swift
import Foundation
import Observation

@Observable
@MainActor
final class OnlineEventsModel {
    private(set) var events: [OnlineEvent]

    /// Le volet affiché. Initialisé sur un jeu qui a du contenu : ouvrir sur un
    /// volet vide alors que l'autre a un événement en cours serait absurde.
    var selectedGame: Game

    private let contentStore: ContentStore<OnlineEvent>?

    init(events: [OnlineEvent], contentStore: ContentStore<OnlineEvent>? = nil) {
        self.events = events
        self.contentStore = contentStore
        self.selectedGame = Self.defaultGame(for: events)
    }

    /// Jeux ayant au moins un événement, dans l'ordre de `Game`. Même règle que
    /// `ProgressionModel.gamesWithChallenges`.
    var availableGames: [Game] {
        Game.allCases.filter { game in events.contains { $0.game == game } }
    }

    /// Pas de sélecteur tant qu'il n'y a rien à choisir : tant que le mode en
    /// ligne à venir n'est pas ouvert, une seule entrée occuperait la place
    /// sans rien offrir.
    var showsGamePicker: Bool {
        availableGames.count > 1
    }

    /// L'événement dont la fenêtre contient `now`, pour le jeu affiché.
    /// `nil` hors de toute fenêtre — la vue dit alors « terminé » plutôt que de
    /// montrer le dernier comme s'il durait encore.
    func currentEvent(at now: Date) -> OnlineEvent? {
        events.first { $0.game == selectedGame && $0.isActive(at: now) }
    }

    /// Le plus récent du jeu affiché, actif ou non. Sert à dire ce qui vient de
    /// se terminer, jamais à le faire passer pour en cours.
    func latestEvent() -> OnlineEvent? {
        events.filter { $0.game == selectedGame }.max { $0.endsAt < $1.endsAt }
    }

    func update(events newEvents: [OnlineEvent]) {
        let hadNothing = events.isEmpty
        events = newEvents
        // Ne réécrit la sélection que si elle n'avait pas pu être faite : un
        // utilisateur qui a choisi un volet ne doit pas le voir changer sous
        // ses yeux à la première synchronisation.
        if hadNothing {
            selectedGame = Self.defaultGame(for: newEvents)
        }
    }

    /// Tirer-pour-rafraîchir. L'échec est silencieux : le geste rend la main et
    /// l'écran garde ce qu'il affichait. Même choix que `FeedModel.refresh()`.
    func refresh() async {
        guard let contentStore else { return }
        try? await contentStore.refresh()
        update(events: contentStore.items)
    }

    private static func defaultGame(for events: [OnlineEvent]) -> Game {
        Game.allCases.first { game in events.contains { $0.game == game } } ?? .reference
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/OnlineEventsModelTests
```

Attendu : 7 tests au vert.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Social/OnlineEventsModel.swift \
        NeonCompassTests/Social/OnlineEventsModelTests.swift
git commit -m "feat(social): le modèle d'écran des événements en ligne

Pas de sélecteur de jeu tant qu'un seul en a — même règle que
gamesWithChallenges. Hors de toute fenêtre, currentEvent rend nil : la vue
dira « terminé » au lieu de montrer le dernier comme s'il durait encore."
```

---

### Task 5: L'écran et l'onglet

**Files:**
- Create: `NeonCompass/Features/Social/SocialScreen.swift`
- Create: `NeonCompass/Features/Social/OnlineEventCard.swift`
- Modify: `NeonCompass/App/AppTab.swift`
- Modify: `NeonCompass/App/RootView.swift`
- Modify: `NeonCompassTests/App/AppTabTests.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `OnlineEventsModel` (T4), `ContentStore<OnlineEvent>`, `BannerAdView`.
- Produces: `AppTab.social`, `struct SocialScreen: View`, `struct OnlineEventCard: View`.

- [ ] **Step 1: Ajouter le cas d'onglet et réactiver le test**

Dans `NeonCompass/App/AppTab.swift` :

```swift
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case feed, cheats, map, social, profile

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .feed: "tab.feed"
        case .cheats: "tab.cheats"
        case .map: "tab.map"
        case .social: "tab.social"
        case .profile: "tab.profile"
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "newspaper"
        case .cheats: "gamecontroller"
        case .map: "map.fill"
        case .social: "person.2"
        case .profile: "person.crop.circle"
        }
    }
}
```

L'ordre place `social` **après** `map` : `CompactTabBar` traite la carte à part et la veut au centre. Avec cinq onglets, `map` est à l'index 2.

Ajouter dans `NeonCompassTests/App/AppTabTests.swift`, à côté de `progressTabIsGone` posé au plan A :

```swift
    /// La carte est au centre, et c'est structurel : `CompactTabBar` la rend
    /// comme un bouton proéminent à part des autres.
    ///
    /// Ce test RESTAURE une couverture qui existait avant le plan A, sous le nom
    /// `fiveTabsWithMapInCenter` : ce plan-là a ramené la barre à quatre onglets,
    /// rendant caduques ses assertions `count == 5` et `tabs[2] == .map`. Le
    /// cinquième onglet les rétablit, et ce test empêche d'y revenir sans s'en
    /// apercevoir. La troisième assertion de l'ancien test (`first == .feed`) a
    /// survécu séparément sous le nom `feedComesFirst`.
    @Test func mapSitsInTheMiddle() {
        let tabs = AppTab.allCases
        #expect(tabs.count == 5)
        #expect(tabs[2] == .map)
    }
```

- [ ] **Step 2: Lancer le test — il doit maintenant passer**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/AppTabTests
```

Attendu : échec de compilation de `RootView.screen(for:)` — le `switch` n'est plus exhaustif. C'est le compilateur qui impose l'étape suivante.

- [ ] **Step 3: Écrire la carte d'événement**

Créer `NeonCompass/Features/Social/OnlineEventCard.swift` :

```swift
import SwiftUI

/// La semaine en cours : ce qui rapporte double, ce qui est en promotion, et
/// combien de temps il reste. Le compte à rebours est le produit — un article
/// raconte la semaine, personne ne prévient qu'elle se termine demain.
struct OnlineEventCard: View {
    let event: OnlineEvent
    let now: Date

    private var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.title.resolved(for: languageCode))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            countdown

            if !event.bonuses.isEmpty {
                section("social.event.bonuses") {
                    ForEach(Array(event.bonuses.enumerated()), id: \.offset) { _, bonus in
                        HStack(alignment: .top) {
                            Text(bonus.activity.resolved(for: languageCode))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(bonus.label.resolved(for: languageCode))
                                .foregroundStyle(NCColor.neonCyan)
                        }
                        .font(NCTypography.body)
                    }
                }
            }

            if !event.discounts.isEmpty {
                section("social.event.discounts") {
                    ForEach(Array(event.discounts.enumerated()), id: \.offset) { _, discount in
                        HStack {
                            Text(discount.item.resolved(for: languageCode))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("social.event.percentOff \(discount.percent)")
                                .foregroundStyle(NCColor.neonCyan)
                        }
                        .font(NCTypography.body)
                    }
                }
            }

            if let podium = event.podiumVehicle {
                section("social.event.podium") {
                    Text(podium.resolved(for: languageCode))
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Jamais un négatif : passé `endsAt`, `remaining` rend nil et on dit que
    /// c'est terminé.
    @ViewBuilder
    private var countdown: some View {
        if let remaining = event.remaining(at: now) {
            let days = Int(remaining) / 86_400
            let hours = (Int(remaining) % 86_400) / 3600
            Text("social.event.remaining \(days) \(hours)")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
        } else {
            Text("social.event.over")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private func section(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }
}
```

- [ ] **Step 4: Écrire l'écran**

Créer `NeonCompass/Features/Social/SocialScreen.swift` :

```swift
import SwiftUI
import SwiftData
// `Timer.publish` vient de Combine, et SwiftUI ne le réexporte pas de façon
// fiable. Aucun autre fichier du dépôt n'importe Combine : c'est le premier.
import Combine

/// L'onglet Social. Lisible sans compte : c'est du contenu éditorial publié,
/// pas de l'UGC. Le compte n'est demandé qu'au palier B2, et seulement pour
/// FIGURER au classement, jamais pour le lire.
struct SocialScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @State private var model: OnlineEventsModel?
    /// Réévalué chaque minute : sans ça le compte à rebours resterait figé sur
    /// la valeur qu'il avait à l'ouverture de l'onglet.
    @State private var now = Date()

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        // La tâche appartient à l'ÉCRAN, jamais au ProgressView : accrochée au
        // ProgressView elle s'annulerait elle-même dès que `model` est assigné.
        // Cf. FeedScreen, où ce défaut avait gardé le fil vide.
        .task { await loadModel() }
        .onReceive(tick) { now = $0 }
    }

    private func content(_ model: OnlineEventsModel) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                    if model.showsGamePicker {
                        Picker(selection: Binding(
                            get: { model.selectedGame },
                            set: { model.selectedGame = $0 }
                        )) {
                            ForEach(model.availableGames) { game in
                                Text(game.shortLabel).tag(game)
                            }
                        } label: {
                            Text("social.game.picker")
                        }
                        .pickerStyle(.segmented)
                    }

                    if let event = model.currentEvent(at: now) {
                        OnlineEventCard(event: event, now: now)
                    } else if let latest = model.latestEvent() {
                        OnlineEventCard(event: latest, now: now)
                    } else {
                        emptyState
                    }
                // Écran de liste : la bannière s'y applique (spec §5), jamais
                // sur la carte en interaction. Posée DANS le défilement, en
                // queue de colonne — même motif que `GuidesListView`.
                //
                // Conditionnée à l'abonnement : le Pro se vend d'abord sur la
                // suppression des pubs. En afficher une à quelqu'un qui a payé
                // pour ne plus en voir est le pire retour possible.
                if !proEntitlementModel.isProEntitled {
                    BannerAdView()
                }
            }
            .padding(20)
        }
        .refreshable { await model.refresh() }
    }

    /// Rien de publié : on le dit, on n'invente pas une semaine.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("social.empty.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
            Text("social.empty.body")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func loadModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<OnlineEvent>.live(
            collectionName: "online_events",
            modelContext: modelContext
        )
        model = OnlineEventsModel(events: contentStore.items, contentStore: contentStore)
        try? await contentStore.syncIfNeeded()
        model?.update(events: contentStore.items)
    }
}
```

Dans `RootView.screen(for:)` :

```swift
        case .social: SocialScreen()
```

- [ ] **Step 5: Ajouter les huit clés au catalogue, dans les cinq langues**

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `tab.social` | Social | Social | Social | Social | Social |
| `social.game.picker` | Game | Jeu | Juego | Gioco | Spiel |
| `social.event.bonuses` | Bonuses | Bonus | Bonificaciones | Bonus | Boni |
| `social.event.discounts` | Discounts | Remises | Descuentos | Sconti | Rabatte |
| `social.event.podium` | Podium vehicle | Véhicule du podium | Vehículo del podio | Veicolo del podio | Podiumsfahrzeug |
| `social.event.percentOff %lld` | −%lld%% | −%lld%% | −%lld%% | −%lld%% | −%lld%% |
| `social.event.remaining %lld %lld` | %lld d %lld h left | Il reste %lld j %lld h | Quedan %lld d %lld h | Restano %lld g %lld h | Noch %lld T %lld Std |
| `social.event.over` | This window is over. | Cette fenêtre est terminée. | Esta ventana ha terminado. | Questa finestra è terminata. | Dieser Zeitraum ist vorbei. |
| `social.empty.title` | Nothing published yet | Rien de publié pour l'instant | Aún no hay nada publicado | Ancora nulla di pubblicato | Noch nichts veröffentlicht |
| `social.empty.body` | The next weekly update will show up here. | La prochaine mise à jour hebdomadaire s'affichera ici. | La próxima actualización semanal aparecerá aquí. | Il prossimo aggiornamento settimanale apparirà qui. | Das nächste wöchentliche Update erscheint hier. |

`social.event.remaining` porte **deux** `%lld` dans le même ordre partout, et `social.event.percentOff` un `%lld` plus un `%%` littéral : `LocalizationCoverageTests.formatSpecifiersMatchAcrossLocales` échoue si une langue en diverge.

- [ ] **Step 6: Lancer la suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : tout au vert, `mapSitsInTheMiddle` compris — le cinquième onglet remet la carte au centre.

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Features/Social/ NeonCompass/App/AppTab.swift NeonCompass/App/RootView.swift \
        NeonCompassTests/App/AppTabTests.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(social): l'onglet Social et la semaine en cours

Se lit sans compte : c'est du contenu éditorial publié, pas de l'UGC.

Le compte à rebours se réévalue chaque minute — sans ça il resterait figé sur
la valeur qu'il avait à l'ouverture. Hors fenêtre, la carte dit « terminé »
plutôt que d'afficher un négatif.

La carte revient au centre de la barre : cinq onglets à nouveau."
```

---

### Task 6: Le rappel local

**Files:**
- Create: `NeonCompass/Core/Notifications/LocalNotificationScheduling.swift`
- Create: `NeonCompass/Core/Online/EventReminderScheduler.swift`
- Create: `NeonCompassTests/Online/EventReminderSchedulerTests.swift`
- Modify: `NeonCompass/Features/Social/SocialScreen.swift`

**Interfaces:**
- Consumes: `OnlineEvent` (T3).
- Produces:
  - `protocol LocalNotificationScheduling: Sendable` avec
    `func requestPermissionIfNeeded() async -> Bool`,
    `func schedule(id: String, title: String, body: String, at: Date) async`,
    `func cancel(ids: [String]) async`
  - `struct EventReminderScheduler: Sendable` avec
    `static func reminderDate(for event: OnlineEvent) -> Date`,
    `static func reminders(for events: [OnlineEvent], at now: Date) -> [(id: String, fireAt: Date)]`

**Pourquoi local et pas un push.** `endsAt` est sur l'appareil dès la synchronisation : le rappel n'a besoin d'aucun serveur, il tombe même hors ligne, et il ne demande aucun compte. C'est ce qui garde tout le palier B1 autonome. La demande d'autorisation vit aujourd'hui sur `FollowedCategoryNotifying`, réservé au Pro — d'où un protocole séparé : le rappel d'événement est **gratuit** (spec fondatrice §5, « les notifications générales restent gratuites »).

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `NeonCompassTests/Online/EventReminderSchedulerTests.swift` :

```swift
import Testing
import Foundation
@testable import NeonCompass

struct EventReminderSchedulerTests {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func event(id: String, endsAt: String) throws -> OnlineEvent {
        try JSONDecoder().decode(OnlineEvent.self, from: Data("""
        { "id": "\(id)", "game": "gtav", "startsAt": "2026-08-06T09:00:00Z",
          "endsAt": "\(endsAt)", "title": { "en": "x" } }
        """.utf8))
    }

    @Test func reminderFiresTwentyFourHoursBeforeTheEnd() throws {
        let event = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        #expect(EventReminderScheduler.reminderDate(for: event) == date("2026-08-12T09:00:00Z"))
    }

    /// Programmer dans le passé ne déclenche rien et encombre : un événement
    /// dont le rappel est déjà passé n'en reçoit pas.
    @Test func noReminderForAPastWindow() throws {
        let event = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        let reminders = EventReminderScheduler.reminders(for: [event], at: date("2026-08-12T18:00:00Z"))
        #expect(reminders.isEmpty)
    }

    @Test func noReminderForAnAlreadyFinishedEvent() throws {
        let event = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        let reminders = EventReminderScheduler.reminders(for: [event], at: date("2026-08-20T00:00:00Z"))
        #expect(reminders.isEmpty)
    }

    @Test func oneReminderPerFutureEvent() throws {
        let a = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        let b = try event(id: "online_b", endsAt: "2026-08-20T09:00:00Z")
        let reminders = EventReminderScheduler.reminders(for: [a, b], at: date("2026-08-06T12:00:00Z"))
        #expect(reminders.count == 2)
        #expect(reminders.map(\.id) == ["online_a", "online_b"])
    }

    /// L'identifiant de rappel est celui de l'événement : reprogrammer à la
    /// synchronisation suivante REMPLACE, ce qui interdit les doublons par
    /// construction plutôt que par un ménage explicite.
    @Test func reminderIdentifierIsTheEventIdentifier() throws {
        let event = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        let reminders = EventReminderScheduler.reminders(for: [event], at: date("2026-08-06T12:00:00Z"))
        #expect(reminders.first?.id == "online_a")
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/EventReminderSchedulerTests
```

Attendu : `cannot find 'EventReminderScheduler' in scope`.

- [ ] **Step 3: Écrire le protocole et son implémentation**

Créer `NeonCompass/Core/Notifications/LocalNotificationScheduling.swift` :

```swift
import Foundation
import UserNotifications

/// Notifications programmées localement, sans serveur.
///
/// Distinct de `FollowedCategoryNotifying`, qui porte les topics FCM des
/// catégories suivies et est réservé au Pro. Le rappel d'événement est gratuit
/// (spec fondatrice §5 : « les notifications générales restent gratuites »),
/// donc il lui faut son propre chemin de demande d'autorisation.
protocol LocalNotificationScheduling: Sendable {
    func requestPermissionIfNeeded() async -> Bool
    func schedule(id: String, title: String, body: String, at fireDate: Date) async
    func cancel(ids: [String]) async
}

/// Implémentation `UserNotifications`. Aucun Firebase ici : ce rappel ne quitte
/// jamais l'appareil.
struct SystemLocalNotificationScheduler: LocalNotificationScheduling {
    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    func schedule(id: String, title: String, body: String, at fireDate: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        // Même identifiant que l'événement : une reprogrammation REMPLACE au
        // lieu d'empiler. C'est ce qui interdit les doublons par construction.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancel(ids: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
```

Créer `NeonCompass/Core/Online/EventReminderScheduler.swift` :

```swift
import Foundation

/// Quoi programmer, et quand. Aucune dépendance à `UserNotifications` : c'est
/// ce qui rend la règle testable sans jamais toucher au centre de notifications.
struct EventReminderScheduler: Sendable {
    /// Vingt-quatre heures avant la fin. Assez tôt pour agir, assez tard pour
    /// que ce soit une urgence — c'est tout l'intérêt du rappel.
    static let leadTime: TimeInterval = 86_400

    static func reminderDate(for event: OnlineEvent) -> Date {
        event.endsAt.addingTimeInterval(-leadTime)
    }

    /// Les rappels encore programmables, dans l'ordre des événements reçus.
    /// Un rappel déjà passé est écarté : le programmer ne déclencherait rien
    /// et encombrerait la file du système.
    static func reminders(for events: [OnlineEvent], at now: Date) -> [(id: String, fireAt: Date)] {
        events.compactMap { event in
            let fireAt = reminderDate(for: event)
            guard fireAt > now else { return nil }
            return (id: event.id, fireAt: fireAt)
        }
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/EventReminderSchedulerTests
```

Attendu : 5 tests au vert.

- [ ] **Step 5: Brancher l'écran dessus**

Dans `SocialScreen.swift`, ajouter la propriété et l'appel après la synchronisation :

```swift
    private let notifications: any LocalNotificationScheduling = SystemLocalNotificationScheduler()
```

À la fin de `loadModel()` :

```swift
        await scheduleReminders(for: contentStore.items)
```

```swift
    /// Reprogrammé à chaque synchronisation : un événement corrigé côté contenu
    /// doit déplacer son rappel, pas en ajouter un second. L'identifiant étant
    /// celui de l'événement, la reprogrammation remplace.
    private func scheduleReminders(for events: [OnlineEvent]) async {
        let pending = EventReminderScheduler.reminders(for: events, at: Date())
        guard !pending.isEmpty else { return }
        guard await notifications.requestPermissionIfNeeded() else { return }
        for reminder in pending {
            await notifications.schedule(
                id: reminder.id,
                title: String(localized: "social.reminder.title"),
                body: String(localized: "social.reminder.body"),
                at: reminder.fireAt
            )
        }
    }
```

- [ ] **Step 6: Ajouter les deux clés au catalogue, dans les cinq langues**

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `social.reminder.title` | Last day | Dernier jour | Último día | Ultimo giorno | Letzter Tag |
| `social.reminder.body` | This week's bonuses end tomorrow. | Les bonus de la semaine se terminent demain. | Las bonificaciones de esta semana terminan mañana. | I bonus di questa settimana finiscono domani. | Die Boni dieser Woche enden morgen. |

- [ ] **Step 7: Lancer la suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : tout au vert.

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Core/Notifications/LocalNotificationScheduling.swift \
        NeonCompass/Core/Online/EventReminderScheduler.swift \
        NeonCompassTests/Online/EventReminderSchedulerTests.swift \
        NeonCompass/Features/Social/SocialScreen.swift \
        NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(social): un rappel local 24 h avant la fin des bonus

Local et pas push : endsAt est sur l'appareil dès la synchronisation, donc
aucune Cloud Function, aucun topic, aucun compte — et le rappel tombe même
hors ligne. C'est ce qui garde tout le palier autonome du serveur.

L'identifiant du rappel est celui de l'événement : reprogrammer remplace au
lieu d'empiler, ce qui interdit les doublons par construction.

Protocole séparé de FollowedCategoryNotifying, qui est réservé au Pro : ce
rappel-ci est gratuit, comme toute notification générale."
```

---

### Task 7: Vérification au simulateur (B1)

Sans test automatisé, et c'est assumé : deux défauts d'UI de la section Codes avaient compilé, passé les tests et bien lu dans leur plan.

- [ ] **Step 1: Publier une fixture d'événement**

```sh
cat > content/online-events/online_gtav_demo.json <<'JSON'
{
  "id": "online_gtav_demo",
  "game": "gtav",
  "startsAt": "2026-07-30T09:00:00Z",
  "endsAt": "2026-08-06T09:00:00Z",
  "title": { "en": "Weekly update", "fr": "Mise à jour de la semaine",
             "es": "Actualización semanal", "it": "Aggiornamento settimanale",
             "de": "Wöchentliches Update" },
  "bonuses": [{ "activity": { "en": "Sea races", "fr": "Courses en mer" },
                "label": { "en": "Double payouts", "fr": "Gains doublés" } }],
  "discounts": [{ "item": { "en": "Speedboat", "fr": "Vedette rapide" }, "percent": 30 }],
  "status": "draft",
  "sources": ["https://gtaboom.com/exemple"],
  "confidence": "multi-source"
}
JSON
cd tools/content-cli && node cli.js validate
```

Attendu : validation au vert.

- [ ] **Step 2: Parcourir la liste de contrôle**

- [ ] L'onglet Social est **visible** dans la barre, la carte est à nouveau au centre
- [ ] La carte de la semaine s'affiche avec bonus, remises et compte à rebours
- [ ] Aucun sélecteur de jeu (un seul jeu a des événements)
- [ ] Le compte à rebours **bouge** — patienter une minute, la valeur doit changer
- [ ] Avec un `endsAt` dans le passé, la carte dit « terminé » et **jamais** un négatif
- [ ] Sans aucun événement, l'état vide s'affiche et ne prétend rien
- [ ] Tirer vers le bas rafraîchit sans vider l'écran en cas d'échec réseau
- [ ] La bannière est en bas, sans recouvrir le dernier élément de la liste
- [ ] L'autorisation de notification est demandée une seule fois, pas à chaque ouverture

- [ ] **Step 3: Vérifier l'iPad**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

- [ ] Cinq entrées dans la sidebar adaptative
- [ ] La carte d'événement ne s'étire pas sur toute la largeur en une ligne illisible

- [ ] **Step 4: Retirer la fixture de démonstration**

```sh
rm content/online-events/online_gtav_demo.json
```

- [ ] **Step 5: Commit des correctifs éventuels**

S'il n'y a rien à corriger, ne rien commiter.

---

# Palier B2 — Le classement des contributeurs

**B1 se suffit à lui-même.** Si le planning se tend avant la soumission de fin octobre, ce palier saute sans laisser de trou dans l'écran.

### Task 8: La Function planifiée

**Files:**
- Create: `functions/src/leaderboard.ts`
- Create: `functions/src/leaderboard.test.ts`
- Create: `functions/src/rebuildLeaderboard.ts`
- Modify: `functions/src/index.ts`

**Interfaces:**
- Consumes: les documents `profiles/{uid}` et `contributions`.
- Produces:
  - `export interface LeaderboardRow { uid: string; handle: string; xp: number; approvedCount: number }`
  - `export function rankProfiles(profiles: LeaderboardInput[], limit: number): LeaderboardRow[]`
  - la Function planifiée `rebuildLeaderboard`

Lire `functions/src/rebuildCommunityBundles.ts` **et** `functions/src/communityBundles.test.ts` avant d'écrire : le motif d'agrégation planifiée vers un document unique et son harnais de test s'en reprennent. Ne pas inventer un second motif.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `functions/src/leaderboard.test.ts` :

```ts
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { rankProfiles } from './leaderboard.js';

const base = { uid: 'u1', handle: 'NEON-FALCON-88', xp: 100, approvedCount: 4, shadowHidden: false };

describe('rankProfiles', () => {
  it('classe par XP décroissante', () => {
    const rows = rankProfiles(
      [{ ...base, uid: 'u1', xp: 100 }, { ...base, uid: 'u2', xp: 300 }, { ...base, uid: 'u3', xp: 200 }],
      50,
    );
    assert.deepEqual(rows.map((r) => r.uid), ['u2', 'u3', 'u1']);
  });

  it('exclut les comptes shadow-bannés', () => {
    const rows = rankProfiles(
      [{ ...base, uid: 'u1', xp: 500, shadowHidden: true }, { ...base, uid: 'u2', xp: 100 }],
      50,
    );
    assert.deepEqual(rows.map((r) => r.uid), ['u2']);
  });

  it('exclut ceux qui n’ont aucune contribution approuvée', () => {
    const rows = rankProfiles(
      [{ ...base, uid: 'u1', xp: 500, approvedCount: 0 }, { ...base, uid: 'u2', xp: 100 }],
      50,
    );
    assert.deepEqual(rows.map((r) => r.uid), ['u2']);
  });

  it('tronque au nombre demandé', () => {
    const many = Array.from({ length: 80 }, (_, i) => ({ ...base, uid: `u${i}`, xp: i }));
    assert.equal(rankProfiles(many, 50).length, 50);
  });

  it('départage à XP égale par identifiant, pour un ordre déterministe', () => {
    const rows = rankProfiles([{ ...base, uid: 'b', xp: 100 }, { ...base, uid: 'a', xp: 100 }], 50);
    assert.deepEqual(rows.map((r) => r.uid), ['a', 'b']);
  });

  it('ne recopie jamais un champ absent du classement public', () => {
    const rows = rankProfiles([{ ...base, uid: 'u1' }], 50);
    assert.deepEqual(Object.keys(rows[0]).sort(), ['approvedCount', 'handle', 'uid', 'xp']);
  });
});
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

```sh
cd functions && npm test
```

Attendu : `Cannot find module './leaderboard.js'`.

- [ ] **Step 3: Écrire le calcul, pur**

Créer `functions/src/leaderboard.ts` :

```ts
export interface LeaderboardInput {
  uid: string;
  handle: string;
  xp: number;
  approvedCount: number;
  shadowHidden: boolean;
}

export interface LeaderboardRow {
  uid: string;
  handle: string;
  xp: number;
  approvedCount: number;
}

/**
 * Classement des contributeurs, sans aucun appel Firestore — c'est ce qui le
 * rend testable, comme la logique de contribution l'est déjà.
 *
 * Classer sur les contributions APPROUVÉES et jamais soumises : c'est la
 * différence entre récompenser la qualité et récompenser le volume, et c'est
 * la modération qui encaisserait la seconde.
 */
export function rankProfiles(profiles: LeaderboardInput[], limit: number): LeaderboardRow[] {
  return profiles
    .filter((p) => !p.shadowHidden && p.approvedCount > 0)
    // Départage par uid à XP égale : sans ça l'ordre dépendrait de celui que
    // Firestore a rendu, et le classement bougerait sans raison d'un run à
    // l'autre.
    .sort((a, b) => b.xp - a.xp || a.uid.localeCompare(b.uid))
    .slice(0, limit)
    .map(({ uid, handle, xp, approvedCount }) => ({ uid, handle, xp, approvedCount }));
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

```sh
cd functions && npm test
```

Attendu : 6 tests au vert, plus les suites existantes.

- [ ] **Step 5: Écrire la Function planifiée**

Créer `functions/src/rebuildLeaderboard.ts`. Reprendre la forme de `rebuildCommunityBundles.ts` — même région, même déclencheur planifié.

```ts
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore } from 'firebase-admin/firestore';
import { rankProfiles, type LeaderboardInput } from './leaderboard.js';

const TOP_N = 50;

/**
 * Agrège le classement dans UN document.
 *
 * Jamais une requête client sur la collection des profils : les Security Rules
 * sont deny-by-default, et la balayer serait à la fois un coût et une fuite.
 * Chaque client lit deux documents — `leaderboards/weekly` et le sien — quel
 * que soit le nombre d'utilisateurs.
 */
export const rebuildLeaderboard = onSchedule(
  { region: 'europe-west1', schedule: 'every day 04:00' },
  async () => {
    const db = getFirestore();
    const snapshot = await db.collection('profiles').get();

    const inputs: LeaderboardInput[] = snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        uid: doc.id,
        handle: data.handle ?? '',
        xp: data.xp ?? 0,
        approvedCount: data.approvedCount ?? 0,
        shadowHidden: data.shadowHidden === true,
      };
    });

    const rows = rankProfiles(inputs, TOP_N);
    await db.doc('leaderboards/weekly').set({ rows, updatedAt: Date.now() });

    // Le rang personnel va dans le document de chacun : c'est ce qui permet au
    // Profil de l'afficher sans lire le classement entier.
    //
    // Découpé en lots : un batch Firestore plafonne à 500 écritures, et cette
    // boucle parcourt TOUS les contributeurs, pas seulement le top 50. Poser la
    // limite maintenant plutôt que de la découvrir le jour où le classement
    // dépasse 500 entrées — c'est-à-dire au pic de sortie.
    const ranked = rankProfiles(inputs, inputs.length);
    const CHUNK = 400;
    for (let i = 0; i < ranked.length; i += CHUNK) {
      const batch = db.batch();
      ranked.slice(i, i + CHUNK).forEach((row, offset) => {
        batch.set(db.doc(`profiles/${row.uid}`), { rank: i + offset + 1 }, { merge: true });
      });
      await batch.commit();
    }
  },
);
```

Exporter dans `functions/src/index.ts`, à côté des autres :

```ts
export { rebuildLeaderboard } from './rebuildLeaderboard.js';
```

Ouvrir la lecture dans `firestore.rules` :

```
    match /leaderboards/{document=**} {
      allow read: if true;
      allow write: if false;
    }
```

- [ ] **Step 6: Lancer la suite complète des Functions**

```sh
cd functions && npm run build && npm test
```

Attendu : compilation TypeScript sans erreur, tous les tests au vert.

- [ ] **Step 7: Commit**

```bash
git add functions/src/leaderboard.ts functions/src/leaderboard.test.ts \
        functions/src/rebuildLeaderboard.ts functions/src/index.ts firestore.rules
git commit -m "feat(social): le classement des contributeurs, agrégé côté serveur

Un seul document lu par client, jamais une requête sur la collection des
profils : les règles sont deny-by-default et la balayer serait un coût et une
fuite. Le rang personnel est déposé dans le document de chacun.

Classé sur les contributions APPROUVÉES, jamais soumises — sinon on récompense
le volume et c'est la modération qui encaisse. Les comptes shadow-bannés en
sont exclus.

Le calcul est pur, sans appel Firestore : c'est ce qui le rend testable."
```

---

### Task 9: La section et le rang personnel

**Files:**
- Create: `NeonCompass/Core/Community/Leaderboard.swift`
- Create: `NeonCompass/Features/Social/LeaderboardSection.swift`
- Create: `NeonCompassTests/Social/LeaderboardTests.swift`
- Modify: `NeonCompass/Features/Social/SocialScreen.swift`
- Modify: `NeonCompass/Features/Profile/ProfileHeaderView.swift`
- Modify: `NeonCompass/Core/Auth/Profile.swift`

**Interfaces:**
- Consumes: `rebuildLeaderboard` (T8), `ServerFeaturesModel`.
- Produces:
  - `struct LeaderboardRow: Codable, Equatable, Identifiable, Sendable { let uid, handle: String; let xp, approvedCount: Int }` (`id` = `uid`)
  - `struct Leaderboard: Codable, Equatable, Sendable { let rows: [LeaderboardRow] }`
  - `protocol LeaderboardRepository: Sendable { func fetchWeekly() async throws -> Leaderboard? }`
  - `ProfileHeaderView.init(profile:isSignedIn:isProEntitled:pendingContributionCount:onOpenSettings:)` **inchangé** — le rang vient de `Profile.rank`, pas d'un paramètre de plus.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `NeonCompassTests/Social/LeaderboardTests.swift` :

```swift
import Testing
import Foundation
@testable import NeonCompass

struct LeaderboardTests {
    @Test func decodesRows() throws {
        let json = Data("""
        { "rows": [
          { "uid": "u1", "handle": "NEON-FALCON-88", "xp": 300, "approvedCount": 12 },
          { "uid": "u2", "handle": "VIOLET-HAWK-04", "xp": 100, "approvedCount": 3 }
        ] }
        """.utf8)
        let board = try JSONDecoder().decode(Leaderboard.self, from: json)
        #expect(board.rows.count == 2)
        #expect(board.rows.first?.handle == "NEON-FALCON-88")
        #expect(board.rows.first?.id == "u1")
    }

    /// Un classement vide n'est pas une erreur : c'est ce que rend la première
    /// exécution, avant qu'aucune contribution n'ait été approuvée.
    @Test func emptyBoardDecodes() throws {
        let board = try JSONDecoder().decode(Leaderboard.self, from: Data(#"{ "rows": [] }"#.utf8))
        #expect(board.rows.isEmpty)
    }

    /// `rank` est déposé par la Function planifiée : il est absent tant qu'elle
    /// n'a pas tourné, et le Profil n'affiche alors pas de ligne de rang.
    @Test func profileDecodesWithoutRank() throws {
        let json = Data("""
        { "handle": "NEON-FALCON-88", "xp": 300, "level": 4, "isPremium": false }
        """.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.rank == nil)
    }

    @Test func profileDecodesWithRank() throws {
        let json = Data("""
        { "handle": "NEON-FALCON-88", "xp": 300, "level": 4, "isPremium": false, "rank": 342 }
        """.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.rank == 342)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/LeaderboardTests
```

Attendu : `cannot find 'Leaderboard' in scope`.

- [ ] **Step 3: Écrire le modèle et son dépôt**

Créer `NeonCompass/Core/Community/Leaderboard.swift` :

```swift
import Foundation

/// Une ligne du classement public. Aucune donnée personnelle : le handle est
/// généré par nous, jamais saisi — c'est ce qui rend ce classement affichable
/// sans une seule ligne de modération.
struct LeaderboardRow: Codable, Equatable, Identifiable, Sendable {
    let uid: String
    let handle: String
    let xp: Int
    let approvedCount: Int

    var id: String { uid }
}

/// Le document unique `leaderboards/weekly`, écrit par la Function planifiée.
struct Leaderboard: Codable, Equatable, Sendable {
    let rows: [LeaderboardRow]
}

protocol LeaderboardRepository: Sendable {
    func fetchWeekly() async throws -> Leaderboard?
}
```

Créer son implémentation réelle, `NeonCompass/Core/Community/FirestoreLeaderboardRepository.swift`, calquée sur `FirestoreProfileRepository` — dont elle reprend le contrat : un document absent rend `nil`, il ne fait pas échouer l'appelant. Ici l'absence est le cas normal tant que la Function planifiée n'a pas tourné une première fois.

```swift
import FirebaseFirestore

/// Lit le document unique écrit par `rebuildLeaderboard`. Une seule lecture par
/// ouverture d'onglet, quel que soit le nombre d'utilisateurs — jamais une
/// requête sur la collection des profils.
final class FirestoreLeaderboardRepository: LeaderboardRepository {
    nonisolated(unsafe) private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func fetchWeekly() async throws -> Leaderboard? {
        let document = try await firestore.collection("leaderboards").document("weekly").getDocument()
        guard document.exists else { return nil }
        return try document.data(as: Leaderboard.self)
    }
}
```

Ajouter le rang à `NeonCompass/Core/Auth/Profile.swift` :

```swift
struct Profile: Codable, Equatable, Sendable {
    var handle: String
    let xp: Int
    let level: Int
    let isPremium: Bool
    /// Déposé par `rebuildLeaderboard`. Absent tant qu'elle n'a pas tourné —
    /// le Profil n'affiche alors pas de ligne de rang, plutôt qu'un zéro faux.
    let rank: Int?
}
```

Toute construction existante de `Profile` (doublures de test comprises) doit recevoir `rank: nil`. Compiler et suivre les erreurs.

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/LeaderboardTests
```

Attendu : 4 tests au vert.

- [ ] **Step 5: Écrire la section, et la brancher**

Créer `NeonCompass/Features/Social/LeaderboardSection.swift` :

```swift
import SwiftUI

/// Le classement des contributeurs. Se lit sans compte — y figurer en demande
/// un, ce que `submitContribution` impose déjà côté serveur.
struct LeaderboardSection: View {
    let rows: [LeaderboardRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("social.leaderboard.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            if rows.isEmpty {
                Text("social.leaderboard.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack {
                            // `verbatim` : un rang nu n'a rien à traduire, mais sans ça
                            // SwiftUI en fait la clé `%lld` et l'extracteur la reverse
                            // dans le catalogue comme une souche vide. Cf. ProgressRing.
                            Text(verbatim: "\(index + 1)")
                                .font(NCTypography.body.bold())
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 32, alignment: .leading)
                            Text(row.handle)
                                .font(NCTypography.body)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("social.leaderboard.spots \(row.approvedCount)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.vertical, 8)
                        if index < rows.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
```

Dans `SocialScreen.swift`, ajouter sous la carte d'événement, gardée par `ServerFeaturesModel` — **absente**, pas vide, quand le serveur est éteint :

```swift
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @State private var leaderboardRows: [LeaderboardRow] = []
    private let leaderboardRepository: any LeaderboardRepository = FirestoreLeaderboardRepository()
```

```swift
                    if serverFeatures.isEnabled {
                        LeaderboardSection(rows: leaderboardRows)
                    }
```

Et le chargement, à la fin de `loadModel()` — après la programmation des rappels :

```swift
        await loadLeaderboard()
```

```swift
    /// Une lecture, gardée par le drapeau serveur : sans Cloud Functions
    /// déployées, `leaderboards/weekly` n'existe pas et l'interroger ne
    /// produirait qu'une erreur silencieuse à chaque ouverture d'onglet.
    ///
    /// L'échec laisse la liste vide, et la section dit alors « aucun spot
    /// approuvé » — état honnête, jamais un écran en erreur.
    private func loadLeaderboard() async {
        guard serverFeatures.isEnabled else { return }
        leaderboardRows = (try? await leaderboardRepository.fetchWeekly())?.rows ?? []
    }
```

`loadModel()` ne s'exécute qu'une fois (`guard model == nil`). Le classement ne bouge qu'une fois par jour : le recharger à chaque apparition de l'onglet serait une lecture Firestore pour rien. `refreshable` reste le geste explicite de rafraîchissement — ajouter `await loadLeaderboard()` dans la fermeture `.refreshable` à côté de `model.refresh()`.

Dans `ProfileHeaderView.swift`, ajouter sous la ligne de niveau :

```swift
                if let rank = profile.rank {
                    Text("profile.rank \(rank)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
```

- [ ] **Step 6: Ajouter les quatre clés au catalogue, dans les cinq langues**

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `social.leaderboard.title` | Top contributors | Meilleurs contributeurs | Mejores colaboradores | Migliori contributori | Top-Beitragende |
| `social.leaderboard.empty` | No approved spots yet. | Aucun spot approuvé pour l'instant. | Aún no hay lugares aprobados. | Nessun luogo approvato per ora. | Noch keine freigegebenen Orte. |
| `social.leaderboard.spots %lld` | %lld spots | %lld spots | %lld lugares | %lld luoghi | %lld Orte |
| `profile.rank %lld` | Rank %lld | %lld en classement | Puesto %lld | Posizione %lld | Platz %lld |

- [ ] **Step 7: Lancer la suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : tout au vert.

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Core/Community/Leaderboard.swift \
        NeonCompass/Core/Community/FirestoreLeaderboardRepository.swift \
        NeonCompass/Features/Social/LeaderboardSection.swift \
        NeonCompassTests/Social/LeaderboardTests.swift \
        NeonCompass/Features/Social/SocialScreen.swift \
        NeonCompass/Features/Profile/ProfileHeaderView.swift \
        NeonCompass/Core/Auth/Profile.swift \
        NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(social): le classement s'affiche, et le rang rejoint le Profil

rank est optionnel : absent tant que la Function planifiée n'a pas tourné, le
Profil n'affiche alors pas de ligne plutôt qu'un zéro faux.

La section disparaît quand ServerFeaturesModel est faux — absente, pas vide."
```

---

## Ce que ce plan ne fait pas

- **La recherche de coéquipiers.** Décrite au spec, pas construite : elle rouvre le dossier Apple 1.2 et ne sert à rien tant que le mode en ligne à venir n'est pas ouvert. Son propre spec et son propre plan, après le lancement.
- **La bascule de `.github/workflows/veille.yml` en quotidien.** Elle concerne toute la chaîne de contenu, pas seulement les événements. Ce plan en dépend sans la faire.
- **Un widget de compte à rebours.** Surface Pro, à réexaminer si l'onglet prend.
- **Un historique des semaines passées.** Un bonus expiré n'intéresse personne.
- **Toute messagerie, tout envoi d'image, tout profil public consultable.**
