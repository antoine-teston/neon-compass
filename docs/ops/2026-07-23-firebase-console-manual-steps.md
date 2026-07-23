# Firebase Console manual steps (not expressible in code)

These steps exist only in the Firebase Console — no CLI or SDK call in this
repo performs them. Run once per environment (dev/prod, per
`docs/superpowers/specs/2026-07-19-neon-compass-companion-design.md`'s
"Environnements & sauvegardes" section).

## 1. App Check enforcement

`enforceAppCheck: true` on the three community callables (Plan 5c, Task 1)
is enforced by the Cloud Functions runtime itself the moment those
functions are **deployed** — there is no separate Console toggle for
callables. This is different from Firestore's own App Check enforcement
(step 2 below), which genuinely is a separate, Console-only switch.

**Consequence: deploying `submitContribution`/`castVote`/`reportContribution`
to a real project immediately rejects any caller without a valid App Check
token** — including debug builds and the Simulator, since this codebase has
no debug-token fallback provider wired up (deliberately, per Task 1's
"App Attest only" design). Do not deploy these three functions to an
environment other people rely on until Step 5's device smoke test has
succeeded, or you will lock out every existing tester on that environment,
not just future ones.

1. Build and run on a **physical** iPhone/iPad (App Attest doesn't work in
   the Simulator) signed with a provisioning profile that has the App
   Attest capability, against a project where these functions are NOT yet
   deployed (or a dedicated dev project you don't mind briefly breaking).
2. Sign in with Apple, then try "Propose a spot" end to end — this will
   fail with an App Check error until Step 3 below is done, which is
   expected the very first time.
3. Deploy the three functions to that project.
4. Retry "Propose a spot" from the same device. Check Firebase Console →
   App Check → Apps → this app: the request should show up as "Verified".
5. **Separately**, for Firestore itself (a different surface — the
   callables enforcing App Check does NOT stop a client from reading/writing
   Firestore directly, bypassing the callables):
   - Firebase Console → App Check → APIs.
   - For **Cloud Firestore**: set enforcement to "Enforced" — only after
     confirming Step 4 above succeeded, for the same lock-out reason.
6. Register the app's App Attest capability under App Check → Apps → (this
   app) — this requires the app's bundle ID and an Apple Developer Program
   membership with the App Attest capability enabled on the App ID (do this
   before Step 1, it's a prerequisite for App Attest to work at all — listed
   last here only because it's a one-time setup step, not a sequential one).

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
no app update or redeploy needed. `submitContribution` checks this live on
every call and rejects new submissions while disabled — this is the actual
enforcement point, not just a UI hint. `castVote` and `reportContribution`
are NOT gated by this flag (voting/reporting on already-approved content is
lower-risk than new spam creation, and was judged not worth the extra
Remote Config fetch on every vote) — if a future incident needs those
stopped too, extend the same check to those functions. Clients pick up the
UI-hiding effect on their next `fetchAndActivate()` (mirrors how
`contentVersion` already works, see `RemoteConfigVersionProvider.swift`),
but that's a UX nicety, not the actual enforcement.
