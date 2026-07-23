# Firebase Console manual steps (not expressible in code)

These steps exist only in the Firebase Console — no CLI or SDK call in this
repo performs them. Run once per environment (dev/prod, per
`docs/superpowers/specs/2026-07-19-neon-compass-companion-design.md`'s
"Environnements & sauvegardes" section).

## 1. App Check enforcement

`enforceAppCheck: true` on the callables (Plan 5c, Task 1) rejects
un-attested requests at the Cloud Functions layer. Firestore itself also
needs App Check enforcement turned on separately, or a client could still
read/write Firestore directly bypassing the callables' check:

1. Firebase Console → App Check → APIs.
2. For **Cloud Firestore**: set enforcement to "Enforced" (only after
   confirming the app registers successfully with App Attest in Step 5
   below — enforcing too early locks out every client, including TestFlight
   builds not yet re-signed).
3. For **Cloud Functions**: same — set to "Enforced" once confirmed working.
4. Register the app's App Attest capability under App Check → Apps → (this
   app) — this requires the app's bundle ID and an Apple Developer Program
   membership with the App Attest capability enabled on the App ID.

## 2. Firebase budget alerts

Spec §"Filets": "alertes de budget Firebase" — a safety net against a
runaway Cloud Functions bill (e.g. from the anti-abuse triggers in this
plan misfiring in a loop).

1. Google Cloud Console → Billing → Budgets & alerts → Create budget.
2. Scope to the Firebase project's billing account.
3. Set thresholds at 50%/90%/100% of your comfort ceiling, notify the
   project owner's email.

## 3. Remote Config kill-switch — first-time setup

Plan 5c, Task 5 adds a `communityContributionsEnabled` Remote Config
parameter, read with a default of `true` if unset. No console action is
strictly required (the Cloud Functions and client both treat a missing
parameter as `true`), but for the kill-switch to be flippable in an
emergency without a code deploy, explicitly create the parameter once:

1. Firebase Console → Remote Config → Add parameter.
2. Key: `communityContributionsEnabled`, type: Boolean, default value: `true`.
3. Publish.

To pull the emergency brake later: flip the value to `false` and publish —
no app update or redeploy needed. Cloud Functions calls poll it live;
clients pick it up on their next `fetchAndActivate()` (mirrors how
`contentVersion` already works, see `RemoteConfigVersionProvider.swift`).
