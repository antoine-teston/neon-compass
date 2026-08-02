# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Neon Compass** — an unofficial iOS companion app for GTA VI (releasing November 19, 2026): stylized interactive map, cheats/guides, progress tracking, community map contributions. Ad-funded, App Store. The validated design lives in `docs/superpowers/specs/2026-07-19-neon-compass-companion-design.md` — read it before making product or architecture decisions. Nothing is scaffolded yet.

Style of this file: Karpathy-minimal. High signal only. If a rule doesn't change a decision, it doesn't belong here. Keep it short as the project grows — prune aggressively.

## Hard constraints

- **IP**: This is an unofficial fan project. Never ship or commit Rockstar/Take-Two assets (logos, artwork, audio, ripped data). All content must be original or clearly transformative fan work. No Rockstar trademarks (GTA, Grand Theft Auto, Vice City, Leonida) in the app name, icon, App Store subtitle, or bundle ID. Aggregated facts are always rewritten in our own words. Generated-image prompts never reference GTA/Rockstar/its characters, and prompts + sources are archived as proof of originality.
  - **Trademarks inside content, decided 2026-08-02.** The ban above is about the app's *identity*. In content, a trademark is allowed in a **nominative** field only — one whose whole value names a third party's product in order to refer to it, which is the same referential use the specialist press relies on. `tools/content-cli/nominative-fields.mjs` enumerates those fields per kind and enforces what buys them the exception: they must stay bare names — no sentence punctuation, eight words max, and never a mark on its own (`GTA` alone names nothing; `GTA+ Shark Cards` names a product). Everywhere we write prose ourselves — `title`, `body`, `note`, `effect`, composed labels — trademarks stay banned. `check-publishable` is the gate, and it applies the name test itself rather than trusting another script to.
- **Target**: iOS/iPadOS 26+, universal iPhone + iPad (no Mac Catalyst). iPad is first-class — companion-beside-the-TV is the core tablet use case; adaptive layouts (`.sidebarAdaptable` tabs, side panel instead of sheets on regular width), never a scaled-up phone UI. iOS 26 minimum is deliberate: native Liquid Glass everywhere, no fallback paths.
- **Design language**: Liquid Glass for all chrome (system tab bar/toolbars, `.glassEffect()` surfaces in `GlassEffectContainer`s); retro synthwave lives in the content layer only. Restraint over decoration — glow on at most three accents per screen.
- **Language**: Swift 6, strict concurrency enabled. SwiftUI only — no UIKit unless a specific API forces it, and then wrapped in one file.
- **Localization**: FR, EN, ES, IT, DE from v1. Every user-facing string goes through the String Catalog — no hardcoded literals.
  - **Direction decided 2026-07-22, not yet migrated**: French becomes the primary/base language (English falls back to it, not the other way around). Today's actual state — `project.yml`'s `developmentLanguage: en`, `LocalizedText`'s required `en` field with fallback-to-`en`, and `content/schema/*.json`'s required `en` field — is still English-primary (built across plans 1-3b before this decision). Do not silently flip individual call sites; the migration is a dedicated future plan touching `LocalizedText`, the content schemas, `project.yml`, and every `resolved(for:)` call site at once.

## Stack decisions (don't relitigate)

- SwiftUI + Observation framework (`@Observable`), not Combine, not TCA.
- SwiftData for persistence.
- Third-party dependencies: Firebase (Firestore, Anonymous Auth, Remote Config, Analytics) and Google Mobile Ads are approved — the ad-funded model requires them. Anything else needs a concrete justification. Swift Package Manager only — no CocoaPods.
- Firebase stays behind protocols in `Core/` — features never import it directly.
- Tests: Swift Testing (`import Testing`), not XCTest, for new tests.

## Commands

Projet `NeonCompass.xcodeproj`, scheme `NeonCompass`, généré par XcodeGen depuis `project.yml` — **relancer `xcodegen generate` après toute création ou suppression de fichier source**, sinon `xcodebuild` rapporte « 0 tests » au lieu d'un échec de compilation.

Le simulateur disponible est `iPhone 17` (iOS 26.5) ; l'iPad est `iPad Pro 13-inch (M5)`.

```sh
# Build
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build

# All tests
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test

# Single test (Swift Testing)
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/SomeSuite/someTest

# Lint / format (once configured)
swiftlint
swiftformat .
```

## Architecture

Feature-first folders (`App/`, `Features/`, `Core/`), pas layer-first.

- One `@Observable` model per feature screen. Views stay dumb.
- **Aucun écran d'onglet n'a de `NavigationStack`.** `RootView` empile les écrans dans un `ZStack` sous une barre d'onglets maison (`CompactTabBar`) en compact, et une `TabView` `.sidebarAdaptable` en régulier. Conséquence à ne pas réapprendre à ses dépens : **un `ToolbarItem` posé sur un écran d'onglet ne s'affiche nulle part, sans erreur ni avertissement.** Ce qui doit vivre dans une barre passe par un bouton dans le contenu, ou par une feuille — celle-ci peut avoir son propre `NavigationStack` et donc sa toolbar.
- Anything touching the network or disk lives in `Core/` behind a protocol so features are testable without I/O.

## Working style

- Small diffs. One feature or fix per session; don't refactor opportunistically.
- Before claiming done: build + tests must pass locally. Paste the failing output if they don't.
- When a decision here conflicts with reality (API deprecated, better tool exists), raise it in the conversation — don't silently deviate.
