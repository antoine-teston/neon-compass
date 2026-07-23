# App Store Connect: Privacy labels & AdMob provisioning (manual steps)

Not expressible in code — App Store Connect configuration and third-party
account provisioning. Spec §"5.1.2/ATT" risk mitigation: "Labels alignés
sur les SDK réels, prompt ATT + UMP."

## 1. Provision the real AdMob account/app

`Task 1` and `Task 4`/`5` of Plan 6a use PLACEHOLDER AdMob unit IDs
(Google's own public test IDs) marked with `// TODO: replace...` comments.
Before any TestFlight/App Store build:

1. Create (or use the existing) AdMob account, add this app.
2. Create ad units: one adaptive banner, one interstitial.
3. Replace `GADApplicationIdentifier` in `NeonCompass/Support/Info-Ads.plist`
   with the real AdMob App ID.
4. Replace the two `adUnitID` placeholders (`AdMobInterstitialProvider.swift`,
   `BannerAdView.swift`) with the real unit IDs.

## 2. App Privacy labels (App Store Connect → App Privacy)

Must accurately reflect every SDK actually linked, not just AdMob:
- **Data Used to Track You**: Device ID (IDFA, via AdMob, gated by ATT).
- **Data Linked to You**: none beyond what Plan 5's account system already
  declares (Sign in with Apple identifier, handle, contribution/level data).
- **Data Not Linked to You**: usage data (Firebase Analytics, if/when
  enabled — confirm current state before publishing labels; Plan 6a does
  not add Firebase Analytics).

Cross-check against the actual SPM dependency graph at submission time —
labels drift silently if a dependency's data-collection behavior changes
between plan-writing time and submission time.

## 3. Privacy policy hosting

Spec requires a hosted privacy policy (referenced from both the UMP consent
form and App Store Connect's privacy-policy URL field). Not part of Plan
6a's code — track as a pre-submission checklist item alongside the
already-planned `docs/privacy/` registry (spec §"Droits & suppression").

## 4. Interstitial trigger moment + Remote Config parameter (follow-up, not this plan)

Plan 6a ships `InterstitialCapPolicy` (the capped, unit-tested decision
primitive) and `AdMobInterstitialProvider`, but does NOT wire either into
an actual trigger moment in the app, and does not create the Remote Config
`interstitialFrequency` parameter itself — the spec doesn't prescribe a
specific trigger ("on returning to Feed after N minutes", "on completing a
checklist item", etc.), and picking one is a product decision. Track this
as a fast, focused follow-up once a trigger UX is chosen — see Plan 6a's
Self-Review section for the full reasoning.
