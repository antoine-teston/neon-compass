# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Neon Compass** — an unofficial iOS companion app for GTA VI (releasing November 19, 2026): stylized interactive map, cheats/guides, progress tracking, community map contributions. Ad-funded, App Store. The validated design lives in `docs/superpowers/specs/2026-07-19-neon-compass-companion-design.md` — read it before making product or architecture decisions. Nothing is scaffolded yet.

Style of this file: Karpathy-minimal. High signal only. If a rule doesn't change a decision, it doesn't belong here. Keep it short as the project grows — prune aggressively.

## Hard constraints

- **IP**: This is an unofficial fan project. Never ship or commit Rockstar/Take-Two assets (logos, artwork, audio, ripped data). All content must be original or clearly transformative fan work. No Rockstar trademarks (GTA, Grand Theft Auto, Vice City, Leonida) in the app name, icon, App Store subtitle, or bundle ID. Aggregated facts are always rewritten in our own words. Generated-image prompts never reference GTA/Rockstar/its characters, and prompts + sources are archived as proof of originality.
- **Target**: iOS/iPadOS 26+, universal iPhone + iPad (no Mac Catalyst). iPad is first-class — companion-beside-the-TV is the core tablet use case; adaptive layouts (`.sidebarAdaptable` tabs, side panel instead of sheets on regular width), never a scaled-up phone UI. iOS 26 minimum is deliberate: native Liquid Glass everywhere, no fallback paths.
- **Design language**: Liquid Glass for all chrome (system tab bar/toolbars, `.glassEffect()` surfaces in `GlassEffectContainer`s); retro synthwave lives in the content layer only. Restraint over decoration — glow on at most three accents per screen.
- **Language**: Swift 6, strict concurrency enabled. SwiftUI only — no UIKit unless a specific API forces it, and then wrapped in one file.
- **Localization**: FR, EN, ES, IT, DE from v1. Development language is English; every user-facing string goes through the String Catalog — no hardcoded literals. Firestore content uses per-language fields with English fallback.

## Stack decisions (don't relitigate)

- SwiftUI + Observation framework (`@Observable`), not Combine, not TCA.
- SwiftData for persistence.
- Third-party dependencies: Firebase (Firestore, Anonymous Auth, Remote Config, Analytics) and Google Mobile Ads are approved — the ad-funded model requires them. Anything else needs a concrete justification. Swift Package Manager only — no CocoaPods.
- Firebase stays behind protocols in `Core/` — features never import it directly.
- Tests: Swift Testing (`import Testing`), not XCTest, for new tests.

## Commands

Project not yet created. Once the Xcode project exists (expected name: `NeonCompass.xcodeproj`, scheme `NeonCompass`):

```sh
# Build
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' build

# All tests
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test

# Single test (Swift Testing)
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:NeonCompassTests/SomeSuite/someTest

# Lint / format (once configured)
swiftlint
swiftformat .
```

Update this section with the real names the moment the project is scaffolded — stale commands are worse than none.

## Architecture (intended)

Feature-first folders, not layer-first:

```
NeonCompass/
  App/            # entry point, root navigation, DI
  Features/       # one folder per feature: View + Model + tests colocated
  Core/           # shared: networking, persistence, design system
```

- One `@Observable` model per feature screen. Views stay dumb.
- Navigation via a single `NavigationStack` path owned at the App level.
- Anything touching the network or disk lives in `Core/` behind a protocol so features are testable without I/O.

## Working style

- Small diffs. One feature or fix per session; don't refactor opportunistically.
- Before claiming done: build + tests must pass locally. Paste the failing output if they don't.
- When a decision here conflicts with reality (API deprecated, better tool exists), raise it in the conversation — don't silently deviate.
