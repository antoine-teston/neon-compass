# Plan 6c — Localisation (String Catalog FR/ES/IT/DE) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every user-facing string in `NeonCompass/Resources/Localizable.xcstrings` gets a real French, Spanish, Italian, and German translation alongside the existing English source, closing out the last sub-plan of roadmap item 6 ("Monétisation & localisation").

**Architecture:** A small, tested Node script (`tools/xcstrings-locale/apply-locale.js`) performs surgical, per-key text insertion into `Localizable.xcstrings` — never a whole-file JSON reparse-and-dump, which has repeatedly corrupted this file's Xcode-specific formatting in earlier plans (see the Global Constraints below). Each of the four languages is applied via the same script fed a flat `key -> translated value` JSON fixture, and a Swift Testing suite verifies every key has all five locales populated with matching `%@`/`%d` format specifiers.

**Tech Stack:** Node.js (ESM, no dependencies — matches `tools/content-cli`'s existing style), Swift Testing.

## Global Constraints

- **Spec (`docs/superpowers/specs/2026-07-19-neon-compass-companion-design.md` §Localisation) and roadmap (`docs/superpowers/plans/2026-07-19-v1-roadmap.md`, item 6):** five languages — FR, EN, ES, IT, DE — from v1. This plan adds fr/es/it/de; en already exists as the source language.
- **CLAUDE.md:** "Every user-facing string goes through the String Catalog — no hardcoded literals." This plan only adds `stringUnit` values to existing keys; it introduces no new UI strings and touches no Swift call sites.
- **CLAUDE.md (2026-07-22 decision, not yet migrated):** French becoming the primary/base language (with English falling back to it) is a **separate, dedicated future plan** touching `LocalizedText`, `content/schema/*.json`, `project.yml`'s `developmentLanguage`, and every `resolved(for:)` call site at once. This plan does **not** touch any of those — `Localizable.xcstrings`'s `sourceLanguage` stays `"en"`, and `project.yml` is untouched.
- **IP constraint (CLAUDE.md, spec §1):** no Rockstar/Take-Two trademarks in translated strings beyond the already-approved disclaimer's factual company-name mentions (which are a required legal disclosure, not a trademark misuse). No new marketing claims are introduced — only translations of existing English copy.
- **Localizable.xcstrings surgical-edit rule (established in Plans 6b-2/6b-3):** never reserialize the whole file via a full JSON parse-then-dump — Xcode's custom serializer uses 2-space indentation and `"key" : value` (space before *and* after the colon), which a generic `JSON.stringify`/`json.dump` does not reproduce, silently reformatting every untouched entry. This plan's tool (Task 1) satisfies this by locating and replacing only the exact byte range for each key's `"localizations"` object, leaving everything else in the file byte-identical — verified in this plan's own Task 1.

## File Structure

- `tools/xcstrings-locale/package.json` — new, `{"type": "module"}`, no dependencies (matches `tools/content-cli`'s existing package.json shape).
- `tools/xcstrings-locale/apply-locale.js` — new. CLI: `node apply-locale.js <locale> <translationsPath>`. Reads `NeonCompass/Resources/Localizable.xcstrings` relative to the repo root, validates the translations file has translations for every existing key (no more, no less) and that the target locale isn't already present for any key, performs the surgical text splice per key, validates the result is still parseable JSON before writing, and errors loudly (throws, non-zero exit) on any problem without touching the file.
- `tools/xcstrings-locale/translations/fr.json`, `es.json`, `it.json`, `de.json` — new. Flat `{ "key": "translated value" }` fixtures, one per language, created in Tasks 1–4 respectively.
- `NeonCompass/Resources/Localizable.xcstrings` — modified in Tasks 1–4 (via the script, never by hand) to add each language's translations.
- `NeonCompassTests/Localization/LocalizationCoverageTests.swift` — new (Task 1). Swift Testing suite reading the raw `.xcstrings` file from disk (same `#filePath`-relative pattern as `NeonCompassTests/Map/POITests.swift:57`, since `NeonCompassTests` isn't hosted in the app process and can't use `Bundle.main`), asserting (a) every key has non-empty `en`/`fr`/`es`/`it`/`de` values and (b) `%@`/`%d`/`%ld`/`%lld` format specifiers appear in the same order/count across all five locales for a given key.
- `docs/ops/2026-07-24-localization-manual-qa.md` — new (Task 5). Manual verification checklist for eyeballing the four new locales on-device/in-Simulator, since this project has no UI test target (confirmed: only a unit test target exists in `project.yml`).

## Task 1: Locale-insertion tool + coverage tests + French

**Files:**
- Create: `tools/xcstrings-locale/package.json`
- Create: `tools/xcstrings-locale/apply-locale.js`
- Create: `tools/xcstrings-locale/translations/fr.json`
- Create: `NeonCompassTests/Localization/LocalizationCoverageTests.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `apply-locale.js`'s exact CLI contract — `node apply-locale.js <locale> <translationsPath>` where `<locale>` is one of `fr`/`es`/`it`/`de` and `<translationsPath>` is a JSON file mapping every key in `Localizable.xcstrings` to its translated string. Exits non-zero (throws) if: the locale isn't one of the four, any key is missing from the translations file, the translations file has a key not present in the catalog, or the target locale already exists for any key. On success, prints `Inserted "<locale>" for <N> keys.` and writes the file only after confirming the result still parses as valid JSON. Tasks 2–4 reuse this script verbatim with their own language's fixture.
- Produces: `LocalizationCoverageTests` — a Swift Testing suite with two `@Test` functions, `everyKeyHasAllFiveLocales()` and `formatSpecifiersMatchAcrossLocales()`, both reading `Localizable.xcstrings` directly from disk. These stay red until Task 4 completes (they check for `fr`, `es`, `it`, and `de` together); this task's own verification step runs them scoped to confirm the `fr` portion of the data is correct without the suite passing outright yet (expected — es/it/de don't exist until Tasks 2–4).

- [ ] **Step 1: Create the tool's `package.json`**

```json
{
  "name": "xcstrings-locale",
  "version": "1.0.0",
  "description": "Surgically inserts locale translations into NeonCompass/Resources/Localizable.xcstrings without reserializing the whole file.",
  "type": "module",
  "main": "apply-locale.js",
  "license": "ISC"
}
```

- [ ] **Step 2: Write `apply-locale.js`**

```js
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
```

- [ ] **Step 3: Create `tools/xcstrings-locale/translations/fr.json`**

```json
{
  "cheats.blocksTrophies": "Désactive les trophées",
  "cheats.platform.picker": "Plateforme",
  "cheats.platform.ps5": "PS5",
  "cheats.platform.xbox": "Xbox",
  "cheats.reader.close": "Terminé",
  "cheats.search.placeholder": "Rechercher des codes",
  "cheatsGuides.section.cheats": "Codes",
  "cheatsGuides.section.guides": "Guides",
  "cheatsGuides.section.picker": "Section",
  "disclaimer.accept": "Compris",
  "disclaimer.body": "Cette application est un projet de fan. Elle n'est ni affiliée à, ni approuvée par, ni liée à Rockstar Games ou Take-Two Interactive. Tous les visuels sont originaux.",
  "disclaimer.title": "Compagnon non officiel",
  "feed.category.announcement": "Annonce",
  "feed.category.event": "Événement",
  "feed.category.patch": "Mise à jour",
  "feed.empty": "Pas encore d'actu — revenez bientôt.",
  "guides.chapter.beginner": "Débutant",
  "guides.chapter.money": "Argent",
  "guides.chapter.sideContent": "Contenu annexe",
  "guides.chapter.story": "Histoire",
  "map.category.activity": "Activités",
  "map.category.collectible": "Objets à collectionner",
  "map.category.event": "Événements",
  "map.category.landmark": "Lieux emblématiques",
  "map.category.safehouse": "Planques",
  "map.category.vehicle": "Véhicules",
  "map.contribution.cancel": "Annuler",
  "map.contribution.categoryLabel": "Catégorie",
  "map.contribution.error": "Une erreur est survenue — réessayez.",
  "map.contribution.sheetTitle": "Proposer un lieu",
  "map.contribution.signInRequired": "Connectez-vous pour proposer un lieu.",
  "map.contribution.submit": "Envoyer",
  "map.contribution.submitted": "Envoyé pour vérification — merci !",
  "map.contribution.titlePlaceholder": "Qu'y a-t-il ici ? (280 caractères max)",
  "map.hideFound.toggle": "Afficher seulement ce qu'il reste",
  "map.longPress.addPersonalPin": "Ajouter une épingle personnelle",
  "map.longPress.cancel": "Annuler",
  "map.longPress.menuTitle": "Que voulez-vous faire ici ?",
  "map.longPress.proposeSpot": "Proposer un lieu",
  "map.personalPins.addPrompt": "Nommez cette épingle",
  "map.personalPins.cancel": "Annuler",
  "map.personalPins.save": "Enregistrer",
  "map.personalPins.title": "Mes épingles",
  "map.routePlanner.button": "Planifier l'itinéraire",
  "map.routePlanner.empty": "Tout a été trouvé — plus rien à parcourir !",
  "map.routePlanner.stepFormat": "Étape %d",
  "map.routePlanner.title": "Itinéraire optimisé",
  "map.search.placeholder": "Rechercher sur la carte",
  "map.spot.blockAuthor": "Masquer les lieux de ce contributeur",
  "map.spot.blockCancel": "Annuler",
  "map.spot.blockConfirm": "Masquer",
  "map.spot.blockConfirmMessage": "Vous ne verrez plus ses lieux. Vous pouvez annuler cette action dans les réglages.",
  "map.spot.blockConfirmTitle": "Masquer les lieux de %@ ?",
  "map.spot.communityBadge": "Communauté",
  "map.spot.report": "Signaler",
  "map.spot.reportSent": "Signalé — merci de nous l'avoir signalé.",
  "paywall.buy": "Débloquer Pro",
  "paywall.close": "Fermer",
  "paywall.feature.ads": "Sans publicité",
  "paywall.feature.notifications": "Notifications pour les lieux suivis",
  "paywall.feature.remaining": "Mode carte « Ce qu'il reste à faire »",
  "paywall.feature.route": "Planificateur d'itinéraire optimisé pour les objets à collectionner",
  "paywall.feature.sync": "Synchronisation cloud entre iPhone et iPad",
  "paywall.feature.themes": "Icônes et thèmes exclusifs",
  "paywall.feature.widgets": "Widgets pour l'écran d'accueil et l'écran verrouillé",
  "paywall.restore": "Restaurer les achats",
  "paywall.subtitle": "Du confort et des outils — jamais les informations.",
  "paywall.title": "Neon Compass Pro",
  "poi.detail.found": "Trouvé",
  "poi.detail.markFound": "Marquer comme trouvé",
  "profile.blockedContributors.empty": "Vous n'avez masqué personne.",
  "profile.blockedContributors.title": "Contributeurs masqués",
  "profile.blockedContributors.unblock": "Réafficher",
  "profile.deleteAccount": "Supprimer le compte",
  "profile.deleteAccount.cancelButton": "Annuler",
  "profile.deleteAccount.confirmButton": "Supprimer",
  "profile.deleteAccount.confirmMessage": "Cela supprime définitivement votre profil. Cette action est irréversible.",
  "profile.deleteAccount.confirmTitle": "Supprimer votre compte ?",
  "profile.followedCategories.title": "M'avertir pour",
  "profile.handle.regenerate": "Régénérer le pseudo",
  "profile.icon.title": "Icône de l'app",
  "profile.myContributions.empty": "Aucune contribution pour l'instant.",
  "profile.myContributions.status.approved": "Approuvé",
  "profile.myContributions.status.pending": "En attente de vérification",
  "profile.myContributions.status.rejected": "Refusé",
  "profile.myContributions.title": "Mes contributions",
  "profile.pro.badge": "PRO",
  "profile.pro.upgradeButton": "Passer à Pro",
  "profile.signIn.prompt": "Connectez-vous pour sauvegarder votre progression sur tous vos appareils et contribuer à la carte.",
  "profile.signOut": "Se déconnecter",
  "profile.theme.title": "Thème",
  "progress.trophies.empty": "Aucun trophée publié pour l'instant — revenez plus près de la sortie.",
  "progress.trophies.title": "Trophées",
  "tab.cheats": "Codes",
  "tab.feed": "Actu",
  "tab.map": "Carte",
  "tab.profile": "Profil",
  "tab.progress": "Progression",
  "theme.cyanPulse": "Pulsation Cyan",
  "theme.magentaDrift": "Dérive Magenta",
  "theme.sunsetOverdrive": "Surtension Crépuscule",
  "widget.description": "Votre progression de collection et votre code favori, en un coup d'œil.",
  "widget.displayName": "Progression Neon Compass",
  "widget.upsell": "Débloquez Pro pour les widgets"
}
```

- [ ] **Step 4: Run the script to apply French**

Run: `node tools/xcstrings-locale/apply-locale.js fr tools/xcstrings-locale/translations/fr.json`
Expected: `Inserted "fr" for 104 keys.` and `git diff --stat NeonCompass/Resources/Localizable.xcstrings` shows only additions (no lines removed except the closing-brace lines that got a trailing comma added).

- [ ] **Step 5: Write the failing coverage tests**

```swift
import Testing
import Foundation

struct LocalizationCoverageTests {
    private static let requiredLocales = ["en", "fr", "es", "it", "de"]

    private static func loadCatalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NeonCompass/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test func everyKeyHasAllFiveLocales() throws {
        let catalog = try Self.loadCatalog()
        let strings = catalog["strings"] as? [String: Any] ?? [:]
        #expect(!strings.isEmpty)

        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                Issue.record("'\(key)' has no localizations dictionary")
                continue
            }
            for locale in Self.requiredLocales {
                let value = (localizations[locale] as? [String: Any])
                    .flatMap { $0["stringUnit"] as? [String: Any] }
                    .flatMap { $0["value"] as? String }
                if value == nil || value?.isEmpty == true {
                    Issue.record("'\(key)' is missing a non-empty '\(locale)' translation")
                }
            }
        }
    }

    @Test func formatSpecifiersMatchAcrossLocales() throws {
        let catalog = try Self.loadCatalog()
        let strings = catalog["strings"] as? [String: Any] ?? [:]

        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }

            var specifiersByLocale: [String: [String]] = [:]
            for locale in Self.requiredLocales {
                guard let value = (localizations[locale] as? [String: Any])
                    .flatMap({ $0["stringUnit"] as? [String: Any] })
                    .flatMap({ $0["value"] as? String }) else { continue }
                specifiersByLocale[locale] = Self.formatSpecifiers(in: value)
            }
            guard let reference = specifiersByLocale["en"] else { continue }
            for locale in Self.requiredLocales.dropFirst() {
                guard let specifiers = specifiersByLocale[locale] else { continue }
                #expect(
                    specifiers == reference,
                    "'\(key)': '\(locale)' format specifiers \(specifiers) don't match 'en' \(reference)"
                )
            }
        }
    }

    private static func formatSpecifiers(in value: String) -> [String] {
        let pattern = /%(@|lld|ld|d)/
        return value.matches(of: pattern).map { String(value[$0.range]) }
    }
}
```

- [ ] **Step 6: Run the tests to confirm current state**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/LocalizationCoverageTests`
Expected: `everyKeyHasAllFiveLocales` FAILS (es/it/de missing for every key — expected, they land in Tasks 2–4). `formatSpecifiersMatchAcrossLocales` PASSES (only checks locales that exist; `fr` was just added and matches `en`).

- [ ] **Step 7: Commit**

```bash
git add tools/xcstrings-locale NeonCompass/Resources/Localizable.xcstrings NeonCompassTests/Localization/LocalizationCoverageTests.swift
git commit -m "feat: xcstrings locale-insertion tool + coverage tests + French translations"
```

## Task 2: Spanish translations

**Files:**
- Create: `tools/xcstrings-locale/translations/es.json`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `tools/xcstrings-locale/apply-locale.js`'s CLI contract from Task 1, unchanged.

- [ ] **Step 1: Create `tools/xcstrings-locale/translations/es.json`**

```json
{
  "cheats.blocksTrophies": "Desactiva los trofeos",
  "cheats.platform.picker": "Plataforma",
  "cheats.platform.ps5": "PS5",
  "cheats.platform.xbox": "Xbox",
  "cheats.reader.close": "Listo",
  "cheats.search.placeholder": "Buscar trucos",
  "cheatsGuides.section.cheats": "Trucos",
  "cheatsGuides.section.guides": "Guías",
  "cheatsGuides.section.picker": "Sección",
  "disclaimer.accept": "Entendido",
  "disclaimer.body": "Esta aplicación es un proyecto de fans. No está afiliada, respaldada ni conectada con Rockstar Games ni Take-Two Interactive. Todas las ilustraciones son originales.",
  "disclaimer.title": "Compañero no oficial",
  "feed.category.announcement": "Anuncio",
  "feed.category.event": "Evento",
  "feed.category.patch": "Parche",
  "feed.empty": "Aún no hay noticias — vuelve pronto.",
  "guides.chapter.beginner": "Principiante",
  "guides.chapter.money": "Dinero",
  "guides.chapter.sideContent": "Contenido secundario",
  "guides.chapter.story": "Historia",
  "map.category.activity": "Actividades",
  "map.category.collectible": "Coleccionables",
  "map.category.event": "Eventos",
  "map.category.landmark": "Lugares emblemáticos",
  "map.category.safehouse": "Refugios",
  "map.category.vehicle": "Vehículos",
  "map.contribution.cancel": "Cancelar",
  "map.contribution.categoryLabel": "Categoría",
  "map.contribution.error": "Algo salió mal — inténtalo de nuevo.",
  "map.contribution.sheetTitle": "Proponer un lugar",
  "map.contribution.signInRequired": "Inicia sesión para proponer un lugar.",
  "map.contribution.submit": "Enviar",
  "map.contribution.submitted": "Enviado para revisión — ¡gracias!",
  "map.contribution.titlePlaceholder": "¿Qué hay aquí? (máx. 280 caracteres)",
  "map.hideFound.toggle": "Mostrar solo lo que falta",
  "map.longPress.addPersonalPin": "Añadir un pin personal",
  "map.longPress.cancel": "Cancelar",
  "map.longPress.menuTitle": "¿Qué quieres hacer aquí?",
  "map.longPress.proposeSpot": "Proponer un lugar",
  "map.personalPins.addPrompt": "Nombra este pin",
  "map.personalPins.cancel": "Cancelar",
  "map.personalPins.save": "Guardar",
  "map.personalPins.title": "Mis pines",
  "map.routePlanner.button": "Planificar ruta",
  "map.routePlanner.empty": "Todo encontrado — ¡no queda nada por recorrer!",
  "map.routePlanner.stepFormat": "Parada %d",
  "map.routePlanner.title": "Ruta optimizada",
  "map.search.placeholder": "Buscar en el mapa",
  "map.spot.blockAuthor": "Ocultar los lugares de este colaborador",
  "map.spot.blockCancel": "Cancelar",
  "map.spot.blockConfirm": "Ocultar",
  "map.spot.blockConfirmMessage": "Ya no verás sus lugares. Puedes deshacer esto en Ajustes.",
  "map.spot.blockConfirmTitle": "¿Ocultar los lugares de %@?",
  "map.spot.communityBadge": "Comunidad",
  "map.spot.report": "Reportar",
  "map.spot.reportSent": "Reportado — gracias por avisarnos.",
  "paywall.buy": "Desbloquear Pro",
  "paywall.close": "Cerrar",
  "paywall.feature.ads": "Sin anuncios",
  "paywall.feature.notifications": "Notificaciones de lugares seguidos",
  "paywall.feature.remaining": "Modo de mapa «Lo que falta por hacer»",
  "paywall.feature.route": "Planificador de rutas optimizado para coleccionables",
  "paywall.feature.sync": "Sincronización en la nube entre iPhone y iPad",
  "paywall.feature.themes": "Iconos y temas exclusivos",
  "paywall.feature.widgets": "Widgets para la pantalla de inicio y la pantalla de bloqueo",
  "paywall.restore": "Restaurar compras",
  "paywall.subtitle": "Comodidad y herramientas — nunca los datos.",
  "paywall.title": "Neon Compass Pro",
  "poi.detail.found": "Encontrado",
  "poi.detail.markFound": "Marcar como encontrado",
  "profile.blockedContributors.empty": "No has ocultado a nadie.",
  "profile.blockedContributors.title": "Colaboradores ocultos",
  "profile.blockedContributors.unblock": "Mostrar de nuevo",
  "profile.deleteAccount": "Eliminar cuenta",
  "profile.deleteAccount.cancelButton": "Cancelar",
  "profile.deleteAccount.confirmButton": "Eliminar",
  "profile.deleteAccount.confirmMessage": "Esto elimina tu perfil de forma permanente. Esta acción no se puede deshacer.",
  "profile.deleteAccount.confirmTitle": "¿Eliminar tu cuenta?",
  "profile.followedCategories.title": "Avisarme sobre",
  "profile.handle.regenerate": "Regenerar el alias",
  "profile.icon.title": "Icono de la app",
  "profile.myContributions.empty": "Aún no hay contribuciones.",
  "profile.myContributions.status.approved": "Aprobado",
  "profile.myContributions.status.pending": "Pendiente de revisión",
  "profile.myContributions.status.rejected": "Rechazado",
  "profile.myContributions.title": "Mis contribuciones",
  "profile.pro.badge": "PRO",
  "profile.pro.upgradeButton": "Mejorar a Pro",
  "profile.signIn.prompt": "Inicia sesión para guardar tu progreso en todos tus dispositivos y contribuir al mapa.",
  "profile.signOut": "Cerrar sesión",
  "profile.theme.title": "Tema",
  "progress.trophies.empty": "Aún no hay trofeos publicados — vuelve más cerca del lanzamiento.",
  "progress.trophies.title": "Trofeos",
  "tab.cheats": "Trucos",
  "tab.feed": "Noticias",
  "tab.map": "Mapa",
  "tab.profile": "Perfil",
  "tab.progress": "Progreso",
  "theme.cyanPulse": "Pulso Cian",
  "theme.magentaDrift": "Deriva Magenta",
  "theme.sunsetOverdrive": "Sobrecarga del Atardecer",
  "widget.description": "Tu progreso de colección y tu truco favorito, de un vistazo.",
  "widget.displayName": "Progreso de Neon Compass",
  "widget.upsell": "Desbloquea Pro para los widgets"
}
```

- [ ] **Step 2: Run the script to apply Spanish**

Run: `node tools/xcstrings-locale/apply-locale.js es tools/xcstrings-locale/translations/es.json`
Expected: `Inserted "es" for 104 keys.`

- [ ] **Step 3: Run the coverage tests**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/LocalizationCoverageTests`
Expected: `everyKeyHasAllFiveLocales` still FAILS (it/de still missing — expected). `formatSpecifiersMatchAcrossLocales` PASSES.

- [ ] **Step 4: Commit**

```bash
git add tools/xcstrings-locale/translations/es.json NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: Spanish translations for the String Catalog"
```

## Task 3: Italian translations

**Files:**
- Create: `tools/xcstrings-locale/translations/it.json`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `tools/xcstrings-locale/apply-locale.js`'s CLI contract from Task 1, unchanged.

- [ ] **Step 1: Create `tools/xcstrings-locale/translations/it.json`**

```json
{
  "cheats.blocksTrophies": "Disattiva i trofei",
  "cheats.platform.picker": "Piattaforma",
  "cheats.platform.ps5": "PS5",
  "cheats.platform.xbox": "Xbox",
  "cheats.reader.close": "Fatto",
  "cheats.search.placeholder": "Cerca trucchi",
  "cheatsGuides.section.cheats": "Trucchi",
  "cheatsGuides.section.guides": "Guide",
  "cheatsGuides.section.picker": "Sezione",
  "disclaimer.accept": "Ho capito",
  "disclaimer.body": "Questa app è un progetto di fan. Non è affiliata, sponsorizzata né collegata a Rockstar Games o Take-Two Interactive. Tutti i contenuti grafici sono originali.",
  "disclaimer.title": "Companion non ufficiale",
  "feed.category.announcement": "Annuncio",
  "feed.category.event": "Evento",
  "feed.category.patch": "Patch",
  "feed.empty": "Ancora nessuna novità — ricontrolla presto.",
  "guides.chapter.beginner": "Principiante",
  "guides.chapter.money": "Denaro",
  "guides.chapter.sideContent": "Contenuti secondari",
  "guides.chapter.story": "Storia",
  "map.category.activity": "Attività",
  "map.category.collectible": "Oggetti da collezione",
  "map.category.event": "Eventi",
  "map.category.landmark": "Punti di riferimento",
  "map.category.safehouse": "Rifugi",
  "map.category.vehicle": "Veicoli",
  "map.contribution.cancel": "Annulla",
  "map.contribution.categoryLabel": "Categoria",
  "map.contribution.error": "Qualcosa è andato storto — riprova.",
  "map.contribution.sheetTitle": "Proponi un luogo",
  "map.contribution.signInRequired": "Accedi per proporre un luogo.",
  "map.contribution.submit": "Invia",
  "map.contribution.submitted": "Inviato per la revisione — grazie!",
  "map.contribution.titlePlaceholder": "Cosa c'è qui? (max 280 caratteri)",
  "map.hideFound.toggle": "Mostra solo ciò che manca",
  "map.longPress.addPersonalPin": "Aggiungi un segnaposto personale",
  "map.longPress.cancel": "Annulla",
  "map.longPress.menuTitle": "Cosa vuoi fare qui?",
  "map.longPress.proposeSpot": "Proponi un luogo",
  "map.personalPins.addPrompt": "Assegna un nome a questo segnaposto",
  "map.personalPins.cancel": "Annulla",
  "map.personalPins.save": "Salva",
  "map.personalPins.title": "I miei segnaposto",
  "map.routePlanner.button": "Pianifica percorso",
  "map.routePlanner.empty": "Hai trovato tutto — nessun percorso da tracciare!",
  "map.routePlanner.stepFormat": "Tappa %d",
  "map.routePlanner.title": "Percorso ottimizzato",
  "map.search.placeholder": "Cerca sulla mappa",
  "map.spot.blockAuthor": "Nascondi i luoghi di questo collaboratore",
  "map.spot.blockCancel": "Annulla",
  "map.spot.blockConfirm": "Nascondi",
  "map.spot.blockConfirmMessage": "Non vedrai più i suoi luoghi. Puoi annullare questa scelta nelle Impostazioni.",
  "map.spot.blockConfirmTitle": "Nascondere i luoghi di %@?",
  "map.spot.communityBadge": "Community",
  "map.spot.report": "Segnala",
  "map.spot.reportSent": "Segnalato — grazie per averlo indicato.",
  "paywall.buy": "Sblocca Pro",
  "paywall.close": "Chiudi",
  "paywall.feature.ads": "Nessuna pubblicità",
  "paywall.feature.notifications": "Notifiche per i luoghi seguiti",
  "paywall.feature.remaining": "Modalità mappa \"Cosa manca da fare\"",
  "paywall.feature.route": "Pianificatore di percorsi ottimizzato per gli oggetti da collezione",
  "paywall.feature.sync": "Sincronizzazione cloud tra iPhone e iPad",
  "paywall.feature.themes": "Icone e temi esclusivi",
  "paywall.feature.widgets": "Widget per schermata Home e schermata di blocco",
  "paywall.restore": "Ripristina acquisti",
  "paywall.subtitle": "Comodità e strumenti — mai i contenuti informativi.",
  "paywall.title": "Neon Compass Pro",
  "poi.detail.found": "Trovato",
  "poi.detail.markFound": "Segna come trovato",
  "profile.blockedContributors.empty": "Non hai nascosto nessuno.",
  "profile.blockedContributors.title": "Collaboratori nascosti",
  "profile.blockedContributors.unblock": "Mostra di nuovo",
  "profile.deleteAccount": "Elimina account",
  "profile.deleteAccount.cancelButton": "Annulla",
  "profile.deleteAccount.confirmButton": "Elimina",
  "profile.deleteAccount.confirmMessage": "Questa azione elimina definitivamente il tuo profilo e non può essere annullata.",
  "profile.deleteAccount.confirmTitle": "Eliminare il tuo account?",
  "profile.followedCategories.title": "Avvisami per",
  "profile.handle.regenerate": "Rigenera il nome utente",
  "profile.icon.title": "Icona dell'app",
  "profile.myContributions.empty": "Ancora nessun contributo.",
  "profile.myContributions.status.approved": "Approvato",
  "profile.myContributions.status.pending": "In attesa di revisione",
  "profile.myContributions.status.rejected": "Rifiutato",
  "profile.myContributions.title": "I miei contributi",
  "profile.pro.badge": "PRO",
  "profile.pro.upgradeButton": "Passa a Pro",
  "profile.signIn.prompt": "Accedi per salvare i tuoi progressi su tutti i dispositivi e contribuire alla mappa.",
  "profile.signOut": "Esci",
  "profile.theme.title": "Tema",
  "progress.trophies.empty": "Nessun trofeo pubblicato ancora — ricontrolla più vicino al lancio.",
  "progress.trophies.title": "Trofei",
  "tab.cheats": "Trucchi",
  "tab.feed": "Novità",
  "tab.map": "Mappa",
  "tab.profile": "Profilo",
  "tab.progress": "Progressi",
  "theme.cyanPulse": "Impulso Ciano",
  "theme.magentaDrift": "Deriva Magenta",
  "theme.sunsetOverdrive": "Sovraccarico al Tramonto",
  "widget.description": "I tuoi progressi di raccolta e il trucco preferito, in un colpo d'occhio.",
  "widget.displayName": "Progressi Neon Compass",
  "widget.upsell": "Sblocca Pro per i widget"
}
```

- [ ] **Step 2: Run the script to apply Italian**

Run: `node tools/xcstrings-locale/apply-locale.js it tools/xcstrings-locale/translations/it.json`
Expected: `Inserted "it" for 104 keys.`

- [ ] **Step 3: Run the coverage tests**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/LocalizationCoverageTests`
Expected: `everyKeyHasAllFiveLocales` still FAILS (de still missing — expected). `formatSpecifiersMatchAcrossLocales` PASSES.

- [ ] **Step 4: Commit**

```bash
git add tools/xcstrings-locale/translations/it.json NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: Italian translations for the String Catalog"
```

## Task 4: German translations

**Files:**
- Create: `tools/xcstrings-locale/translations/de.json`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `tools/xcstrings-locale/apply-locale.js`'s CLI contract from Task 1, unchanged.

- [ ] **Step 1: Create `tools/xcstrings-locale/translations/de.json`**

```json
{
  "cheats.blocksTrophies": "Deaktiviert Trophäen",
  "cheats.platform.picker": "Plattform",
  "cheats.platform.ps5": "PS5",
  "cheats.platform.xbox": "Xbox",
  "cheats.reader.close": "Fertig",
  "cheats.search.placeholder": "Cheats durchsuchen",
  "cheatsGuides.section.cheats": "Cheats",
  "cheatsGuides.section.guides": "Guides",
  "cheatsGuides.section.picker": "Bereich",
  "disclaimer.accept": "Verstanden",
  "disclaimer.body": "Diese App ist ein Fanprojekt. Sie steht in keiner Verbindung zu Rockstar Games oder Take-Two Interactive und wird von diesen weder unterstützt noch anerkannt. Alle Grafiken sind Originalwerke.",
  "disclaimer.title": "Inoffizieller Begleiter",
  "feed.category.announcement": "Ankündigung",
  "feed.category.event": "Event",
  "feed.category.patch": "Update",
  "feed.empty": "Noch keine News — schau bald wieder vorbei.",
  "guides.chapter.beginner": "Einsteiger",
  "guides.chapter.money": "Geld",
  "guides.chapter.sideContent": "Nebeninhalte",
  "guides.chapter.story": "Story",
  "map.category.activity": "Aktivitäten",
  "map.category.collectible": "Sammelobjekte",
  "map.category.event": "Events",
  "map.category.landmark": "Sehenswürdigkeiten",
  "map.category.safehouse": "Unterschlüpfe",
  "map.category.vehicle": "Fahrzeuge",
  "map.contribution.cancel": "Abbrechen",
  "map.contribution.categoryLabel": "Kategorie",
  "map.contribution.error": "Etwas ist schiefgelaufen — versuch es erneut.",
  "map.contribution.sheetTitle": "Ort vorschlagen",
  "map.contribution.signInRequired": "Melde dich an, um einen Ort vorzuschlagen.",
  "map.contribution.submit": "Absenden",
  "map.contribution.submitted": "Zur Prüfung eingereicht — danke!",
  "map.contribution.titlePlaceholder": "Was ist hier? (max. 280 Zeichen)",
  "map.hideFound.toggle": "Nur Verbleibendes anzeigen",
  "map.longPress.addPersonalPin": "Persönliche Markierung hinzufügen",
  "map.longPress.cancel": "Abbrechen",
  "map.longPress.menuTitle": "Was möchtest du hier tun?",
  "map.longPress.proposeSpot": "Ort vorschlagen",
  "map.personalPins.addPrompt": "Markierung benennen",
  "map.personalPins.cancel": "Abbrechen",
  "map.personalPins.save": "Speichern",
  "map.personalPins.title": "Meine Markierungen",
  "map.routePlanner.button": "Route planen",
  "map.routePlanner.empty": "Alles gefunden — keine Route mehr nötig!",
  "map.routePlanner.stepFormat": "Stopp %d",
  "map.routePlanner.title": "Optimierte Route",
  "map.search.placeholder": "Karte durchsuchen",
  "map.spot.blockAuthor": "Orte dieses Mitwirkenden ausblenden",
  "map.spot.blockCancel": "Abbrechen",
  "map.spot.blockConfirm": "Ausblenden",
  "map.spot.blockConfirmMessage": "Du siehst die Orte dieser Person nicht mehr. Du kannst das in den Einstellungen rückgängig machen.",
  "map.spot.blockConfirmTitle": "Orte von %@ ausblenden?",
  "map.spot.communityBadge": "Community",
  "map.spot.report": "Melden",
  "map.spot.reportSent": "Gemeldet — danke für den Hinweis.",
  "paywall.buy": "Pro freischalten",
  "paywall.close": "Schließen",
  "paywall.feature.ads": "Keine Werbung",
  "paywall.feature.notifications": "Benachrichtigungen für verfolgte Orte",
  "paywall.feature.remaining": "Kartenmodus „Was noch zu tun ist“",
  "paywall.feature.route": "Optimierter Routenplaner für Sammelobjekte",
  "paywall.feature.sync": "Cloud-Synchronisierung zwischen iPhone und iPad",
  "paywall.feature.themes": "Exklusive App-Icons und Designs",
  "paywall.feature.widgets": "Widgets für Home- und Sperrbildschirm",
  "paywall.restore": "Käufe wiederherstellen",
  "paywall.subtitle": "Komfort und Werkzeuge — niemals die Fakten.",
  "paywall.title": "Neon Compass Pro",
  "poi.detail.found": "Gefunden",
  "poi.detail.markFound": "Als gefunden markieren",
  "profile.blockedContributors.empty": "Du hast noch niemanden ausgeblendet.",
  "profile.blockedContributors.title": "Ausgeblendete Mitwirkende",
  "profile.blockedContributors.unblock": "Wieder einblenden",
  "profile.deleteAccount": "Konto löschen",
  "profile.deleteAccount.cancelButton": "Abbrechen",
  "profile.deleteAccount.confirmButton": "Löschen",
  "profile.deleteAccount.confirmMessage": "Dadurch wird dein Profil dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.",
  "profile.deleteAccount.confirmTitle": "Konto löschen?",
  "profile.followedCategories.title": "Benachrichtige mich über",
  "profile.handle.regenerate": "Namen neu generieren",
  "profile.icon.title": "App-Symbol",
  "profile.myContributions.empty": "Noch keine Beiträge.",
  "profile.myContributions.status.approved": "Genehmigt",
  "profile.myContributions.status.pending": "Prüfung ausstehend",
  "profile.myContributions.status.rejected": "Abgelehnt",
  "profile.myContributions.title": "Meine Beiträge",
  "profile.pro.badge": "PRO",
  "profile.pro.upgradeButton": "Auf Pro upgraden",
  "profile.signIn.prompt": "Melde dich an, um deinen Fortschritt geräteübergreifend zu speichern und zur Karte beizutragen.",
  "profile.signOut": "Abmelden",
  "profile.theme.title": "Design",
  "progress.trophies.empty": "Noch keine Trophäen veröffentlicht — schau näher am Release wieder vorbei.",
  "progress.trophies.title": "Trophäen",
  "tab.cheats": "Cheats",
  "tab.feed": "News",
  "tab.map": "Karte",
  "tab.profile": "Profil",
  "tab.progress": "Fortschritt",
  "theme.cyanPulse": "Cyan-Puls",
  "theme.magentaDrift": "Magenta-Drift",
  "theme.sunsetOverdrive": "Sonnenuntergangs-Overdrive",
  "widget.description": "Dein Sammelfortschritt und dein Lieblings-Cheat auf einen Blick.",
  "widget.displayName": "Neon Compass Fortschritt",
  "widget.upsell": "Pro freischalten für Widgets"
}
```

- [ ] **Step 2: Run the script to apply German**

Run: `node tools/xcstrings-locale/apply-locale.js de tools/xcstrings-locale/translations/de.json`
Expected: `Inserted "de" for 104 keys.`

- [ ] **Step 3: Run the full coverage suite — should now pass**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/LocalizationCoverageTests`
Expected: both `everyKeyHasAllFiveLocales` and `formatSpecifiersMatchAcrossLocales` PASS.

- [ ] **Step 4: Commit**

```bash
git add tools/xcstrings-locale/translations/de.json NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: German translations for the String Catalog"
```

## Task 5: Full-suite verification + manual QA checklist

**Files:**
- Create: `docs/ops/2026-07-24-localization-manual-qa.md`

**Interfaces:**
- Consumes: nothing new — this task only verifies the result of Tasks 1–4 and documents manual follow-up.

- [ ] **Step 1: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all suites pass (including `LocalizationCoverageTests`), same count as before this plan plus the 2 new tests.

- [ ] **Step 2: Build both schemes**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`. (Only `Localizable.xcstrings` content changed — no new Swift symbols — so this is a sanity check that adding four languages to the String Catalog didn't trip Xcode's string-catalog compiler on any escaping edge case, e.g. `paywall.feature.remaining`'s embedded quotes.)

- [ ] **Step 3: Write the manual QA checklist**

```markdown
# Localization manual QA — FR/ES/IT/DE

Not expressible as an automated test — this project has no UI test target
(only a unit test target, confirmed in `project.yml`), so eyeballing the
four new languages on real screens needs a manual pass before release.

## How to switch language in Simulator

1. `xcrun simctl` doesn't reliably force in-app language for a SwiftUI app
   using the String Catalog — instead, in the running Simulator: Settings →
   General → Language & Region → iPhone Language, pick French/Spanish/
   Italian/German, wait for the Simulator to relaunch its Springboard.
2. Reinstall/launch Neon Compass from Xcode after switching — cold-launch,
   not resume, or the old language's in-memory strings may still be visible
   until fully relaunched.

## What to check per language

1. All 5 tabs (Map, Cheats/Guides, News, Progress, Profile) render without
   any English fallback text or truncated/overflowing labels — French and
   German strings run noticeably longer than English (e.g.
   `paywall.feature.route` / `paywall.feature.widgets`), check they don't
   clip inside the paywall's feature list or the tab bar labels.
2. The onboarding disclaimer (`disclaimer.title`/`disclaimer.body`) reads
   naturally and still legally names "Rockstar Games" / "Take-Two
   Interactive" (untranslated proper nouns — confirm they weren't
   accidentally transliterated).
3. `map.routePlanner.stepFormat` ("Stop %d" / "Étape %d" / etc.) renders
   the number correctly positioned in each language's route-planner sheet.
4. `map.spot.blockConfirmTitle` ("Hide %@'s spots?" / etc.) renders a real
   contributor handle in place of `%@` without broken punctuation around it
   (French/German use different quote-adjacent spacing conventions).
5. The widget (`widget.displayName`/`widget.description`/`widget.upsell`)
   picks up the device's language when added to a Home Screen — the widget
   extension has no separate language setting of its own.

## Known limitation carried over from Plan 6b-3

Push notification body text remains English-only regardless of the
device's language (`functions/src/notifyFollowedCategory.ts` sends a plain
server-side string, not a String Catalog key) — this was disclosed in Plan
6b-3's Self-Review and is unchanged by this plan.

## Not in scope (per CLAUDE.md's 2026-07-22 decision)

French becoming the primary/base language (with English as the fallback,
not the reverse) is a separate future plan — this plan only added fr/es/it/de
alongside the existing English source; `Localizable.xcstrings`'s
`sourceLanguage` and `project.yml`'s `developmentLanguage` both stay `en`.
```

- [ ] **Step 4: Commit**

```bash
git add docs/ops/2026-07-24-localization-manual-qa.md
git commit -m "docs: manual QA checklist for FR/ES/IT/DE, note French-primary migration is out of scope"
```

## Self-Review

**Spec coverage:** Roadmap item 6's "String Catalogs FR/EN/ES/IT/DE" requirement is fully covered — all 104 existing keys now have en/fr/es/it/de. The CLAUDE.md French-primary migration is explicitly out of scope and called out in both the Global Constraints and Task 5's doc, per the CLAUDE.md instruction that it "must not be silently flipped."

**Placeholder scan:** No TBD/TODO — every task has complete, real translated content and a fully-written script/test file.

**Type consistency:** `apply-locale.js`'s CLI contract (`node apply-locale.js <locale> <translationsPath>`) is identical across Tasks 1–4. `LocalizationCoverageTests`'s two `@Test` functions are written once in Task 1 and never redefined.

**Verified before writing this plan:** the exact insertion script (byte-identical to Task 1's Step 2) was run against a scratch copy of the real `Localizable.xcstrings` for all four languages in sequence, confirmed valid JSON after each step, confirmed all 104 keys end up with exactly `{en, fr, es, it, de}` localizations, and confirmed every untouched key's `en` block stays byte-identical to before. All four languages' translation fixtures were cross-checked programmatically against the real key list (no missing/extra keys, 104 each) and for `%@`/`%d` format-specifier parity against the English source before being written into this plan.
