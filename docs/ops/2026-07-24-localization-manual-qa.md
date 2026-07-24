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
