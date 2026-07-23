# Widgets & Push Notifications: manual setup steps

Not expressible in code — Apple Developer portal + Firebase Console
configuration. Spec §"Pro": "Widgets... Notifications suivies."

## 1. App ID capabilities (Apple Developer portal)

1. App Groups: enable on the main app's App ID, register
   `group.co.antoineteston.neoncompass` (must match `WidgetSummary.appGroupID`
   and both targets' entitlements files exactly — already wired in code as
   of Plan 6b-3 Task 1, this step is the Apple-side registration to match).
2. Push Notifications: enable on the main app's App ID.
3. Regenerate/download provisioning profiles reflecting both new
   capabilities before the next TestFlight/device build — a stale
   profile will fail code signing with a capability mismatch, not a
   clear "you forgot a step" error.

## 2. APNs key (Firebase Console)

1. Apple Developer portal → Keys → create an APNs Authentication Key
   (one key covers all environments, unlike the older per-environment
   certificate model).
2. Firebase Console → Project Settings → Cloud Messaging → upload the
   APNs key (needs Key ID + Team ID).

## 3. `aps-environment` entitlement value at release

`NeonCompass.entitlements` (Plan 6b-3 Task 2) ships `aps-environment:
development`. Before an App Store/TestFlight release build, this must be
`production`. This plan did not determine whether XcodeGen's
build-configuration-scoped entitlement values apply cleanly here — confirm
this at release time; if it doesn't, a manual flip in the release
branch/tag process is the fallback, and should be added to whatever
release checklist eventually exists (none does yet, per Plan 7's still-TBD
scope).

## 4. Test the full push path

1. Follow a category in-app (Profile → Notify me about) — this will
   prompt for push permission at that point (not at launch), per this
   plan's design.
2. From the Firebase Console → Cloud Messaging → Send test message → topic
   `spots-<category>`, confirm delivery on a physical device (APNs/FCM
   don't reliably deliver to the Simulator).
3. Approve a real pending contribution of that category via
   `tools/content-cli moderate:approve <id>` (Plan 5c) and confirm the
   Cloud Function-triggered push arrives end-to-end, not just the manual
   test-message path.

## 5. Widget verification

1. Add the "Neon Compass Progress" widget to a home screen on a physical
   device or Simulator (Simulator widget rendering is reliable, unlike
   push delivery).
2. Confirm it shows the Pro upsell placeholder for a non-Pro/signed-out
   install, and the real progress ring + favorite cheat title once Pro is
   purchased/restored (should update within moments — Plan 6b-3 Task 1's
   fix wires this to refresh immediately on entitlement change, not just
   on the widget's own periodic timeline reload).
3. Lock Screen widget family and zone-based (as opposed to category-based)
   following are both intentionally deferred — see the plan document's
   Self-Review for why.
