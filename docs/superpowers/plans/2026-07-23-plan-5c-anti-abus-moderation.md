# Plan 5c — Anti-abus, modération, App Check — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out "Comptes & communauté" (spec §5, Plan 5 of the roadmap) by adding the defense-in-depth layer the spec requires before the contribution system (Plan 5b) can be trusted at scale: App Check, cooldown, geo-dedup, vocabulary filter, velocity monitoring + shadow-ban, a solo-operator moderation workflow, XP/leveling on approval and on votes received, and a Remote Config kill-switch.

**Architecture:** All new server-side checks live inside the existing `submitContribution`/`castVote` Cloud Functions (Plan 5b) plus one new Firestore trigger (`flagSuspiciousContribution`, `onDocumentCreated`) for velocity monitoring. Moderation is a CLI workflow extending the existing `tools/content-cli` (same service-account/Admin-SDK pattern already used for editorial content publish) — there is no in-app admin UI in v1 (solo operator, spec risk table: "Modération débordée (solo) → texte court uniquement, votes en pré-filtre, kill-switch"). App Check is a client SDK integration + Cloud Functions enforcement flag; its correctness can only be confirmed on a physical device, so this plan's App Check task ends with a device smoke test the human operator runs, not something a subagent can verify itself.

**Tech Stack:** Firebase App Check (App Attest provider), Cloud Functions (Node 22, TypeScript, ESM, firebase-functions v6), Firestore triggers, Remote Config (Admin SDK server-side, client SDK), Node CLI (`tools/content-cli`).

## Global Constraints

- **Never an automatic block of a legitimate user.** Velocity monitoring flags submissions for priority human review and can trigger a shadow-ban — it never auto-rejects or auto-bans (spec §"Anti-spam & anti-abus", point 5). A shadow-banned user's own contributions still look normal *to them* (still readable via `fetchMine`, still shown in their own Profile history) — only public visibility (`fetchApproved`) is suppressed.
- **No daily cap or pending-submission limit, ever.** Only a short (minute-order) cooldown between two submissions. A prolific legitimate contributor is never throttled beyond that (spec point 3 — this is an explicit, deliberate product choice, not an oversight to "fix" later).
- **Sign in with Apple identity makes bans permanent** — nothing in this plan creates a path to reset a shadow-ban by reinstalling or re-signing-in (the identity is stable by construction, already true from Plan 5's Sign in with Apple integration; this plan must not undermine that by, e.g., keying anything off a device identifier instead of `uid`).
- **Level is calculated server-side only**, on both of the two spec-mandated triggers: contribution approval and votes received (spec §"Profil & leveling": "le niveau est calculé côté serveur... jamais par le client"). No client code computes or displays a level derived from anything other than `profiles/{uid}.level` as written by a Cloud Function or moderation script.
- **Grades are original, synthwave-themed — never GTA/Rockstar rank names** (spec §"Profil & leveling").
- **Nothing is public before moderation.** This was already true from Plan 5b's Security Rules (`contributions` readable publicly only if `status == 'approved'`) — this plan must not weaken that, including for shadow-banned users' content (their approved-but-shadow-banned spots must still fail the public-visibility query, not just be client-side-filtered).
- **Firebase stays behind protocols in `Core/`** — any new client-side check (e.g., the kill-switch gate) follows the same pattern as `ContentVersionProviding`/`RemoteConfigVersionProvider`.
- **Firestore decoding** always uses `document.data(as:)` on the Swift side, never `JSONSerialization.data(withJSONObject:)` (see Plan 5's Critical bug, Plan 5b's Global Constraints — same rule applies to every new read in this plan).
- **Swift 6 strict concurrency**, `nonisolated(unsafe)` on Firebase SDK handle properties, matching established precedent.
- **Moderation CLI credentials**: same `FIREBASE_SERVICE_ACCOUNT_PATH` environment variable already used by `tools/content-cli publish`/`deploy-rules` — never a second credential mechanism.
- **This plan does not touch StoreKit/Pro entitlements, AdMob, or localization migration** — those are Plan 6.

---

## File Structure

```
functions/src/
  submitContribution.ts        # MODIFIED: cooldown + vocabulary filter + geo-dedup checks
  contribution.ts               # MODIFIED: add vocabulary-filter + geo-dedup pure helpers
  contribution.test.ts          # MODIFIED: new test cases for the above
  castVote.ts                   # MODIFIED: award XP to the contribution author on a net-new upvote
  xp.ts                         # NEW: pure XP/level helpers (levelForXP, GRADE_NAMES), unit-tested
  xp.test.ts                    # NEW
  flagSuspiciousContribution.ts # NEW: Firestore onDocumentCreated trigger, velocity monitoring
  index.ts                      # MODIFIED: export flagSuspiciousContribution

firestore.rules                 # MODIFIED: contributions read rule excludes shadow-banned authors' spots from public visibility

NeonCompass/Core/Community/
  CommunityGateProviding.swift        # NEW: protocol, mirrors ContentVersionProviding
  RemoteConfigCommunityGateProvider.swift  # NEW: Remote Config-backed implementation

NeonCompass/Features/Map/MapScreen.swift        # MODIFIED: hide "Propose a spot" when the kill-switch is off
NeonCompass/Features/Community/CommunityModel.swift  # MODIFIED: exposes contributionsEnabled

NeonCompass/App/NeonCompassApp.swift            # MODIFIED: App Check provider factory registration
project.yml                                     # MODIFIED: add FirebaseAppCheck SPM product

tools/content-cli/cli.js               # MODIFIED: moderate:list / moderate:approve / moderate:reject / shadow-ban / lift-shadow-ban commands
tools/content-cli/firestore-client.js  # MODIFIED: moderation helper functions + Remote Config kill-switch helpers

docs/ops/2026-07-23-firebase-console-manual-steps.md  # NEW: App Check enforcement toggle, Firebase budget alerts — steps that only exist in the Firebase Console, not in code
```

---

### Task 1: App Check (App Attest)

**Files:**
- Modify: `project.yml`
- Modify: `NeonCompass/App/NeonCompassApp.swift`
- Create: `docs/ops/2026-07-23-firebase-console-manual-steps.md`

**Interfaces:**
- Produces: nothing consumed by later Swift tasks (App Check is transparent to callers — the SDK attaches tokens to every Firestore/Functions request automatically once configured). Later tasks assume App Check enforcement is ON for `submitContribution`/`castVote`/`reportContribution` at the Firebase Console level (a manual step this task documents but cannot perform itself).

- [ ] **Step 1: Add the App Check SPM product to `project.yml`**

Find the existing `Firebase:` dependency block (it lists `FirebaseCore`, `FirebaseFirestore`, `FirebaseRemoteConfig`, `FirebaseAuth`, `FirebaseFunctions` as separate `- package: Firebase` / `product: ...` entries). Add one more entry to the same list:

```yaml
      - package: Firebase
        product: FirebaseAppCheck
```

- [ ] **Step 2: Register the App Attest provider factory in `NeonCompassApp.swift`**

Current file:
```swift
import FirebaseCore
import SwiftData
import SwiftUI

@main
struct NeonCompassApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self, TrophyProgress.self, BlockedContributor.self])
    }
}
```

Change to:

```swift
import FirebaseAppCheck
import FirebaseCore
import SwiftData
import SwiftUI

@main
struct NeonCompassApp: App {
    init() {
        // App Check must be configured BEFORE FirebaseApp.configure() —
        // registering the provider factory late means the first few
        // Firestore/Functions calls after launch go out without a token.
        AppCheck.setAppCheckProviderFactory(NeonCompassAppCheckProviderFactory())
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self, TrophyProgress.self, BlockedContributor.self])
    }
}

/// App Attest is the only provider used — it proves the request comes from
/// this app's signed binary running on a real device (spec §"Anti-spam &
/// anti-abus", point 1). No debug-token fallback is wired up in production
/// code; if a simulator smoke test is ever needed, it requires a separate
/// debug-only build configuration, not a runtime branch here.
final class NeonCompassAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}
```

- [ ] **Step 3: Enforce App Check on the three community Cloud Functions**

In `functions/src/submitContribution.ts`, `functions/src/castVote.ts`, `functions/src/reportContribution.ts`, change the `onCall({ region: 'europe-west1' }, ...)` options object in each to also require App Check:

```typescript
onCall({ region: 'europe-west1', enforceAppCheck: true }, async (request) => {
```

With `enforceAppCheck: true`, a request without a valid App Check token is rejected by the platform before the handler body runs — `request.auth` checks still apply on top of this, unchanged.

- [ ] **Step 4: Write the ops doc for the Firebase-Console-only steps**

```markdown
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
```

- [ ] **Step 5: Build to confirm the SPM product resolves and the code compiles**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **` (this confirms `FirebaseAppCheck` resolved via SPM and the provider factory compiles — it does NOT confirm App Attest actually works at runtime, which requires Step 6).

- [ ] **Step 6: Manual device smoke test — human operator, not a subagent**

This step cannot be performed by an implementer subagent (no simulator support for App Attest, and no physical device access in this environment). Hand off to the project owner:

1. Build and run on a **physical** iPhone/iPad (App Attest doesn't work in the Simulator) signed with a provisioning profile that has the App Attest capability.
2. Sign in with Apple, then try "Propose a spot" end to end.
3. Check Firebase Console → App Check → Apps → this app: a request should show up as "Verified".
4. Only after this succeeds, follow `docs/ops/2026-07-23-firebase-console-manual-steps.md` §1 to flip enforcement to "Enforced" for both Firestore and Cloud Functions.

Do not mark this task's Cloud Functions changes as safe to merge with enforcement already flipped to "Enforced" in Firebase Console — `enforceAppCheck: true` in code is inert until enforcement is turned on server-side, so merging the code is safe at any time, but flipping the Console toggle before Step 6 succeeds would lock out every existing signed-in user immediately.

- [ ] **Step 7: Commit**

```bash
git add project.yml NeonCompass/App/NeonCompassApp.swift functions/src/submitContribution.ts functions/src/castVote.ts functions/src/reportContribution.ts docs/ops/2026-07-23-firebase-console-manual-steps.md
git commit -m "feat: App Check (App Attest) provider + enforceAppCheck on community callables"
```

---

### Task 2: `submitContribution` hardening — cooldown, vocabulary filter, geo-dedup

**Files:**
- Modify: `functions/src/contribution.ts`
- Modify: `functions/src/contribution.test.ts`
- Modify: `functions/src/submitContribution.ts`

**Interfaces:**
- Produces: `containsBannedVocabulary(text: string): boolean`, `isTooCloseToExistingSpot(candidate: {x: number; y: number}, existing: Array<{x: number; y: number}>, thresholdNormalized: number): boolean`, `DEDUP_THRESHOLD_NORMALIZED = 0.02`, `COOLDOWN_SECONDS = 60` — all exported from `contribution.ts`, all pure/unit-testable (no Firestore access), consumed by `submitContribution.ts`.

- [ ] **Step 1: Add the pure helpers to `contribution.ts`**

Append to the existing file (after `validateSubmission`):

```typescript
// Minimal, hand-curated banned-vocabulary list — same philosophy as
// handle.ts's word lists: small, deliberately curated, extend by hand.
// This is NOT a moderation replacement, just a first-pass filter to catch
// the most obvious spam/abuse before a human ever sees it (spec point 2).
const BANNED_VOCABULARY = [/\bfuck\b/i, /\bshit\b/i, /\bnigger\b/i, /\bcunt\b/i, /https?:\/\//i];

export function containsBannedVocabulary(text: string): boolean {
  return BANNED_VOCABULARY.some((pattern) => pattern.test(text));
}

export const DEDUP_THRESHOLD_NORMALIZED = 0.02;

// Rejects a submission if an existing (already-approved) spot of the same
// category sits within a small radius in normalized [0,1] map coordinates
// (spec point 2: "déduplication géographique"). Plain Euclidean distance is
// sufficient — the map is a single schematic image, not a geographic
// projection needing haversine-style math.
export function isTooCloseToExistingSpot(
  candidate: { x: number; y: number },
  existing: Array<{ x: number; y: number }>,
  thresholdNormalized: number = DEDUP_THRESHOLD_NORMALIZED
): boolean {
  return existing.some((point) => {
    const dx = point.x - candidate.x;
    const dy = point.y - candidate.y;
    return Math.sqrt(dx * dx + dy * dy) < thresholdNormalized;
  });
}

export const COOLDOWN_SECONDS = 60;
```

- [ ] **Step 2: Add test cases to `contribution.test.ts`**

Append:

```typescript
import { containsBannedVocabulary, isTooCloseToExistingSpot, DEDUP_THRESHOLD_NORMALIZED } from './contribution.js';

test('containsBannedVocabulary flags an obvious banned token', () => {
  assert.equal(containsBannedVocabulary('this spot is shit'), true);
});

test('containsBannedVocabulary flags a raw URL (spam vector)', () => {
  assert.equal(containsBannedVocabulary('check out https://example.com'), true);
});

test('containsBannedVocabulary allows clean text', () => {
  assert.equal(containsBannedVocabulary('Great rooftop view at sunset'), false);
});

test('isTooCloseToExistingSpot rejects a near-duplicate position', () => {
  const existing = [{ x: 0.5, y: 0.5 }];
  assert.equal(isTooCloseToExistingSpot({ x: 0.505, y: 0.505 }, existing), true);
});

test('isTooCloseToExistingSpot allows a position outside the threshold', () => {
  const existing = [{ x: 0.5, y: 0.5 }];
  assert.equal(isTooCloseToExistingSpot({ x: 0.9, y: 0.9 }, existing), false);
});

test('isTooCloseToExistingSpot allows any position when nothing exists yet', () => {
  assert.equal(isTooCloseToExistingSpot({ x: 0.5, y: 0.5 }, []), false);
});

test('DEDUP_THRESHOLD_NORMALIZED is the documented 0.02', () => {
  assert.equal(DEDUP_THRESHOLD_NORMALIZED, 0.02);
});
```

- [ ] **Step 3: Wire the checks into `submitContribution.ts`**

Read the current file (from Plan 5b) before editing — it currently: checks auth, validates via `validateSubmission`, reads `authorHandle` from `profiles/{uid}`, writes the contribution doc. Add, in this order, after the existing `authorHandle` read and before the `db.collection('contributions').add(...)` call:

```typescript
  const profileData = profileSnapshot.data();

  // Cooldown (spec point 3): minute-order gap between two submissions, no
  // daily cap, no pending-submission limit — see this plan's Global
  // Constraints for why that's deliberate, not a gap to close later.
  const lastSubmissionAt = profileData?.lastSubmissionAt as FirebaseFirestore.Timestamp | undefined;
  if (lastSubmissionAt) {
    const secondsSinceLastSubmission = (Date.now() - lastSubmissionAt.toMillis()) / 1000;
    if (secondsSinceLastSubmission < COOLDOWN_SECONDS) {
      throw new HttpsError('resource-exhausted', `Please wait before submitting again (${Math.ceil(COOLDOWN_SECONDS - secondsSinceLastSubmission)}s).`);
    }
  }

  if (containsBannedVocabulary(input.title)) {
    throw new HttpsError('invalid-argument', 'Submission contains disallowed content.');
  }

  const nearbySnapshot = await db
    .collection('contributions')
    .where('status', '==', 'approved')
    .where('category', '==', input.category)
    .get();
  const nearbyPositions = nearbySnapshot.docs.map((doc) => doc.data().position as { x: number; y: number });
  if (isTooCloseToExistingSpot(input.position, nearbyPositions)) {
    throw new HttpsError('already-exists', 'A spot of this category already exists nearby.');
  }
```

And after the successful `db.collection('contributions').add(...)` call, before the `return { id: docRef.id };` line, add:

```typescript
  await db.doc(`profiles/${uid}`).update({ lastSubmissionAt: FieldValue.serverTimestamp() });
```

Add the new import at the top of the file:

```typescript
import { validateSubmission, containsBannedVocabulary, isTooCloseToExistingSpot, COOLDOWN_SECONDS } from './contribution.js';
```//replacing the existing `import { validateSubmission } from './contribution.js';` line.

- [ ] **Step 4: Run tests**

Run: `cd functions && npm test`
Expected: all tests pass (new cases in `contribution.test.ts` + all pre-existing).

- [ ] **Step 5: Commit**

```bash
git add functions/src/contribution.ts functions/src/contribution.test.ts functions/src/submitContribution.ts
git commit -m "feat: submitContribution cooldown, vocabulary filter, geo-dedup"
```

---

### Task 3: XP/leveling + velocity monitoring + shadow-ban

**Files:**
- Create: `functions/src/xp.ts`
- Create: `functions/src/xp.test.ts`
- Create: `functions/src/flagSuspiciousContribution.ts`
- Modify: `functions/src/castVote.ts`
- Modify: `functions/src/index.ts`
- Modify: `firestore.rules`

**Interfaces:**
- Produces: `levelForXP(xp: number): number`, `GRADE_NAMES: string[]` (index = level), `awardXP(db, uid, amount)` (Firestore transaction helper — not unit-testable without an emulator, kept thin, calls `levelForXP`).
- Consumes: `applyVoteDelta` (Task 2 of Plan 5b, `functions/src/vote.ts`, unchanged) for detecting a net-new upvote.

- [ ] **Step 1: Write `xp.ts`**

```typescript
// functions/src/xp.ts
// Pure XP→level mapping — original synthwave-themed grade names, never a
// GTA/Rockstar rank (spec §"Profil & leveling"). Extend the two arrays
// together by hand if more levels are added; they must stay the same length.
export const LEVEL_THRESHOLDS = [0, 50, 150, 400, 900, 2000];
export const GRADE_NAMES = ['SIGNAL', 'PULSE', 'DRIFT', 'CIRCUIT', 'OVERDRIVE', 'SYNTHWAVE ICON'];

export function levelForXP(xp: number): number {
  let level = 0;
  for (let i = 0; i < LEVEL_THRESHOLDS.length; i++) {
    if (xp >= LEVEL_THRESHOLDS[i]) {
      level = i;
    }
  }
  return level;
}

export const XP_PER_APPROVED_CONTRIBUTION = 20;
export const XP_PER_UPVOTE_RECEIVED = 2;

// Applies an XP delta to a profile and recomputes its level in the same
// transaction — the only place in this codebase that mutates
// profiles/{uid}.xp or .level (spec: level is server-computed, never by the
// client, on both approval and votes-received).
export async function awardXP(
  db: FirebaseFirestore.Firestore,
  uid: string,
  amount: number
): Promise<void> {
  const profileRef = db.doc(`profiles/${uid}`);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(profileRef);
    const currentXP = (snapshot.data()?.xp as number | undefined) ?? 0;
    const newXP = currentXP + amount;
    transaction.update(profileRef, { xp: newXP, level: levelForXP(newXP) });
  });
}
```

- [ ] **Step 2: Write `xp.test.ts`**

```typescript
// functions/src/xp.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { levelForXP, LEVEL_THRESHOLDS, GRADE_NAMES } from './xp.js';

test('levelForXP is 0 below the first threshold', () => {
  assert.equal(levelForXP(0), 0);
  assert.equal(levelForXP(49), 0);
});

test('levelForXP steps up exactly at each threshold', () => {
  for (let i = 0; i < LEVEL_THRESHOLDS.length; i++) {
    assert.equal(levelForXP(LEVEL_THRESHOLDS[i]), i);
  }
});

test('levelForXP caps at the highest defined level for very large XP', () => {
  assert.equal(levelForXP(1_000_000), LEVEL_THRESHOLDS.length - 1);
});

test('LEVEL_THRESHOLDS and GRADE_NAMES stay in sync', () => {
  assert.equal(LEVEL_THRESHOLDS.length, GRADE_NAMES.length);
});

test('no grade name is a GTA/Rockstar trademark token', () => {
  const forbidden = /GTA|ROCKSTAR|VICE CITY|LEONIDA/i;
  for (const name of GRADE_NAMES) {
    assert.doesNotMatch(name, forbidden);
  }
});
```

- [ ] **Step 3: Award XP for a net-new upvote in `castVote.ts`**

Read the current file (from Plan 5b) — it runs a transaction reading `contributionSnapshot`/`voteSnapshot`, computes `delta` via `applyVoteDelta`, writes the vote doc and updates the contribution's counts, then returns `{upvotes, downvotes}`. After the transaction resolves successfully (outside the `runTransaction` call, since `awardXP` runs its own separate transaction and Firestore doesn't support nested transactions), add:

```typescript
  const authorUid = contributionSnapshotAuthorUid; // see note below
  if (delta.upvoteDelta > 0 && authorUid) {
    await awardXP(db, authorUid, XP_PER_UPVOTE_RECEIVED * delta.upvoteDelta);
  }

  return result;
```

You'll need to capture the contribution's `authorUid` and the computed `delta` from inside the transaction so they're available after it — the transaction currently returns only `{upvotes, downvotes}`; extend what it returns internally to also include `authorUid` and `delta`, then destructure after `await db.runTransaction(...)`, and return only `{upvotes, downvotes}` from the outer function (the client-facing response shape must not change — `FirebaseContributionFunctions.castVote` on the Swift side already decodes exactly `{upvotes, downvotes}` and nothing else). Add the import:

```typescript
import { awardXP, XP_PER_UPVOTE_RECEIVED } from './xp.js';
```

Do not award XP for downvotes, and do not claw back XP if a vote is retracted or switched away — this plan deliberately keeps vote-driven XP one-directional (see this task's Self-Review note).

- [ ] **Step 4: Write `flagSuspiciousContribution.ts` (velocity monitoring)**

```typescript
// functions/src/flagSuspiciousContribution.ts
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const VELOCITY_WINDOW_SECONDS = 300; // 5 minutes
const VELOCITY_THRESHOLD = 5; // more than this many submissions by the same author in the window is suspicious

// Never auto-rejects or auto-blocks (spec point 5: "jamais un blocage
// automatique d'utilisateur légitime") — only marks the document for
// priority human review and, on a repeated pattern, shadow-bans the author.
// A shadow-ban does not delete or hide the author's OWN view of their
// content (still readable via fetchMine) — it only removes future/existing
// approved spots from the public fetchApproved() query (see firestore.rules
// and Task 4's approve-command note in this same plan).
export const flagSuspiciousContribution = onDocumentCreated(
  { region: 'europe-west1', document: 'contributions/{contributionId}' },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const data = snapshot.data();
    const authorUid = data.authorUid as string | null;
    if (!authorUid) return;

    const db = getFirestore();
    const windowStart = Timestamp.fromMillis(Date.now() - VELOCITY_WINDOW_SECONDS * 1000);
    const recentSnapshot = await db
      .collection('contributions')
      .where('authorUid', '==', authorUid)
      .where('createdAt', '>=', windowStart)
      .get();

    if (recentSnapshot.size <= VELOCITY_THRESHOLD) return;

    await snapshot.ref.update({ flaggedForReview: true });

    // Repeated bursts (this isn't the author's first flagged burst) escalate
    // to a shadow-ban rather than re-flagging forever — the moderation CLI
    // (Task 4) also allows a human to shadow-ban/lift manually at any time.
    const profileRef = db.doc(`profiles/${authorUid}`);
    const profileSnapshot = await profileRef.get();
    const alreadyFlaggedCount = (profileSnapshot.data()?.flaggedBurstCount as number | undefined) ?? 0;
    if (alreadyFlaggedCount >= 1) {
      await profileRef.update({ isShadowBanned: true, flaggedBurstCount: alreadyFlaggedCount + 1 });
    } else {
      await profileRef.update({ flaggedBurstCount: alreadyFlaggedCount + 1 });
    }
  }
);
```

- [ ] **Step 5: Export the trigger from `index.ts`**

```typescript
export { flagSuspiciousContribution } from './flagSuspiciousContribution.js';
```

- [ ] **Step 6: Update `firestore.rules` — shadow-banned authors excluded from public visibility**

This requires the public list query itself to filter shadow-banned authors' spots (Firestore rules validate list queries against their *constraints*, not per-document — a query missing the right `where` clause is rejected outright, it doesn't get silently filtered). Read the current `contributions` rule block (from Plan 5b):

```
    match /contributions/{id} {
      allow read: if resource.data.status == 'approved'
        || (request.auth != null && request.auth.uid == resource.data.authorUid);
      allow write: if false;
    }
```

This rule already covers the shadow-ban case correctly AS WRITTEN, because shadow-banned status lives on the *profile*, not the contribution — a public reader has no rule-visible way to check "is this author shadow-banned" without an extra `get()` inside the rule (expensive, and not how this codebase does cross-document rule checks elsewhere). Instead, this plan makes shadow-banning work by having the moderation CLI (Task 4) write a per-contribution `shadowHidden: true` flag onto EACH of a newly-shadow-banned author's already-approved contributions at the moment of shadow-banning (batched), and having `submitContribution` check the author's `isShadowBanned` profile flag and stamp `shadowHidden: true` directly onto any NEW contribution from a shadow-banned author at creation time. Update the rule to:

```
    match /contributions/{id} {
      allow read: if (resource.data.status == 'approved' && resource.data.shadowHidden != true)
        || (request.auth != null && request.auth.uid == resource.data.authorUid);
      allow write: if false;
    }
```

Go back and add to `submitContribution.ts` (right after the `profileData` read from Step 3 of Task 2): read `profileData?.isShadowBanned === true` and, if so, include `shadowHidden: true` in the new contribution doc's fields (default `shadowHidden: false` otherwise, so `FirestoreContributionRepository`'s `Body` struct — unchanged, it doesn't decode this field, native Firestore Codable ignores unmodeled fields — never needs to know about it).

- [ ] **Step 7: Run tests**

Run: `cd functions && npm test`
Expected: all tests pass, including new `xp.test.ts` cases.

- [ ] **Step 8: Start the Firestore emulator briefly to confirm the updated rules compile**

Run: `firebase emulators:start --only firestore` (Ctrl+C once it logs it's running)
Expected: no rules-compilation error.

- [ ] **Step 9: Commit**

```bash
git add functions/src/xp.ts functions/src/xp.test.ts functions/src/flagSuspiciousContribution.ts functions/src/castVote.ts functions/src/submitContribution.ts functions/src/index.ts firestore.rules
git commit -m "feat: XP/leveling on approval and votes received, velocity monitoring + shadow-ban"
```

---

### Task 4: Moderation CLI

**Files:**
- Modify: `tools/content-cli/firestore-client.js`
- Modify: `tools/content-cli/cli.js`

**Interfaces:**
- Consumes: `xp.ts`'s `XP_PER_APPROVED_CONTRIBUTION`/`levelForXP` logic — reimplemented in plain JS here (the CLI is a separate Node package from `functions/`, no shared build step between them in this repo; duplicating ~10 lines of pure arithmetic is simpler and safer than introducing a cross-package import for a two-file constant).

- [ ] **Step 1: Add moderation + shadow-ban helpers to `firestore-client.js`**

Append to the existing file:

```javascript
// Mirrors functions/src/xp.ts's levelForXP — duplicated intentionally (see
// Task 4's Interfaces note: this CLI is a separate package, not built
// alongside functions/).
const LEVEL_THRESHOLDS = [0, 50, 150, 400, 900, 2000];
function levelForXP(xp) {
  let level = 0;
  for (let i = 0; i < LEVEL_THRESHOLDS.length; i++) {
    if (xp >= LEVEL_THRESHOLDS[i]) level = i;
  }
  return level;
}
const XP_PER_APPROVED_CONTRIBUTION = 20;

export async function listPendingContributions() {
  const db = getFirestore(app());
  const snapshot = await db.collection('contributions').where('status', '==', 'pending').get();
  // Flagged-for-review first (velocity monitoring's priority-review signal,
  // spec point 5), then oldest first within each group.
  return snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => {
      if (Boolean(a.flaggedForReview) !== Boolean(b.flaggedForReview)) {
        return a.flaggedForReview ? -1 : 1;
      }
      return (a.createdAt?.toMillis() ?? 0) - (b.createdAt?.toMillis() ?? 0);
    });
}

export async function approveContribution(contributionId) {
  const db = getFirestore(app());
  const contributionRef = db.collection('contributions').doc(contributionId);
  const snapshot = await contributionRef.get();
  if (!snapshot.exists) throw new Error(`contribution ${contributionId} not found`);
  const authorUid = snapshot.data().authorUid;

  await contributionRef.update({ status: 'approved' });

  if (authorUid) {
    const profileRef = db.doc(`profiles/${authorUid}`);
    await db.runTransaction(async (transaction) => {
      const profileSnapshot = await transaction.get(profileRef);
      const currentXP = profileSnapshot.data()?.xp ?? 0;
      const newXP = currentXP + XP_PER_APPROVED_CONTRIBUTION;
      transaction.update(profileRef, { xp: newXP, level: levelForXP(newXP) });
    });
  }
}

export async function rejectContribution(contributionId) {
  const db = getFirestore(app());
  await db.collection('contributions').doc(contributionId).update({ status: 'rejected' });
}

export async function shadowBanUser(uid) {
  const db = getFirestore(app());
  await db.doc(`profiles/${uid}`).update({ isShadowBanned: true });
  const ownContributions = await db.collection('contributions').where('authorUid', '==', uid).get();
  const batch = db.batch();
  ownContributions.docs.forEach((doc) => batch.update(doc.ref, { shadowHidden: true }));
  await batch.commit();
}

export async function liftShadowBan(uid) {
  const db = getFirestore(app());
  await db.doc(`profiles/${uid}`).update({ isShadowBanned: false });
  const ownContributions = await db.collection('contributions').where('authorUid', '==', uid).get();
  const batch = db.batch();
  ownContributions.docs.forEach((doc) => batch.update(doc.ref, { shadowHidden: false }));
  await batch.commit();
}

export async function getCommunityContributionsEnabled() {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  return template.parameters.communityContributionsEnabled?.defaultValue?.value !== 'false';
}

export async function setCommunityContributionsEnabled(enabled) {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  template.parameters.communityContributionsEnabled = {
    defaultValue: { value: enabled ? 'true' : 'false' },
  };
  await rc.publishTemplate(template);
}
```

- [ ] **Step 2: Wire the new commands into `cli.js`**

Add new `case` branches to the existing `switch (cmd)` block (before the `default:` case), and update the `usage:` message in `default:` to list them:

```javascript
  case 'moderate:list':
    try {
      const { listPendingContributions } = await import('./firestore-client.js');
      const pending = await listPendingContributions();
      if (!pending.length) {
        console.log('moderate:list: nothing pending');
      } else {
        pending.forEach((c) => {
          const flag = c.flaggedForReview ? ' [FLAGGED]' : '';
          console.log(`${c.id}${flag} — [${c.category}] "${c.title}" by ${c.authorHandle}`);
        });
      }
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'moderate:approve':
    try {
      const [id] = flags;
      if (!id) throw new Error('usage: cli.js moderate:approve <contributionId>');
      const { approveContribution } = await import('./firestore-client.js');
      await approveContribution(id);
      console.log(`moderate:approve: ${id} approved`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'moderate:reject':
    try {
      const [id] = flags;
      if (!id) throw new Error('usage: cli.js moderate:reject <contributionId>');
      const { rejectContribution } = await import('./firestore-client.js');
      await rejectContribution(id);
      console.log(`moderate:reject: ${id} rejected`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'shadow-ban':
    try {
      const [uid] = flags;
      if (!uid) throw new Error('usage: cli.js shadow-ban <uid>');
      const { shadowBanUser } = await import('./firestore-client.js');
      await shadowBanUser(uid);
      console.log(`shadow-ban: ${uid} shadow-banned, existing approved spots hidden`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'lift-shadow-ban':
    try {
      const [uid] = flags;
      if (!uid) throw new Error('usage: cli.js lift-shadow-ban <uid>');
      const { liftShadowBan } = await import('./firestore-client.js');
      await liftShadowBan(uid);
      console.log(`lift-shadow-ban: ${uid} restored, existing spots visible again`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
  case 'kill-switch':
    try {
      const [state] = flags.filter((f) => f !== '--dry-run');
      const { getCommunityContributionsEnabled, setCommunityContributionsEnabled } = await import('./firestore-client.js');
      if (!state) {
        const enabled = await getCommunityContributionsEnabled();
        console.log(`kill-switch: community contributions currently ${enabled ? 'ENABLED' : 'DISABLED'}`);
      } else if (state === 'on' || state === 'off') {
        await setCommunityContributionsEnabled(state === 'on');
        console.log(`kill-switch: community contributions now ${state === 'on' ? 'ENABLED' : 'DISABLED'}`);
      } else {
        throw new Error("usage: cli.js kill-switch [on|off]  (no argument = show current state)");
      }
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
```

And update the final `default:` case's usage string to append `|moderate:list|moderate:approve <id>|moderate:reject <id>|shadow-ban <uid>|lift-shadow-ban <uid>|kill-switch [on|off]`.

Note: these new commands read `flags` — check the existing `const [cmd, ...flags] = process.argv.slice(2);` line still gives you what you need; `flags` for e.g. `moderate:approve abc123` is `['abc123']`.

- [ ] **Step 3: Manual smoke test against the Firestore emulator**

```bash
export FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/a/dev-project/service-account.json  # never prod for a smoke test
node tools/content-cli/cli.js moderate:list
```
Expected: runs without crashing (empty result is fine if there's no pending data in that environment — this is a wiring smoke test, not a full integration test with seeded data).

- [ ] **Step 4: Commit**

```bash
git add tools/content-cli/firestore-client.js tools/content-cli/cli.js
git commit -m "feat: moderation CLI (approve/reject, shadow-ban, kill-switch)"
```

---

### Task 5: Remote Config kill-switch — client side

**Files:**
- Create: `NeonCompass/Core/Community/CommunityGateProviding.swift`
- Create: `NeonCompass/Core/Community/RemoteConfigCommunityGateProvider.swift`
- Modify: `NeonCompass/Features/Community/CommunityModel.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: none new from earlier tasks in this plan.
- Produces: `CommunityGateProviding.isEnabled() async throws -> Bool`, `CommunityModel.contributionsEnabled: Bool` (defaults `true`, refreshed via a new `refreshContributionsEnabled() async` call).

- [ ] **Step 1: Write `CommunityGateProviding.swift`**

```swift
import Foundation

/// Abstraction over the Remote Config kill-switch — mirrors
/// ContentVersionProviding's pattern (Core/Content). A missing/unset
/// parameter is treated as enabled (fail-open for a feature that's
/// supplementary, not core — spec §"Contributions utilisateurs": "jamais
/// le plan A du démarrage").
protocol CommunityGateProviding: Sendable {
    func isEnabled() async throws -> Bool
}
```

- [ ] **Step 2: Write `RemoteConfigCommunityGateProvider.swift`**

```swift
@preconcurrency import FirebaseRemoteConfig

final class RemoteConfigCommunityGateProvider: CommunityGateProviding {
    nonisolated(unsafe) private let remoteConfig: RemoteConfig

    init(remoteConfig: RemoteConfig = RemoteConfig.remoteConfig()) {
        self.remoteConfig = remoteConfig
    }

    func isEnabled() async throws -> Bool {
        _ = try await remoteConfig.fetchAndActivate()
        let value = remoteConfig.configValue(forKey: "communityContributionsEnabled")
        // No explicit "does this key exist" API on ConfigValue — an unset
        // key resolves boolValue to false, which would fail-closed
        // (wrong default, see this file's doc comment). Treat an empty
        // source (.static, meaning Remote Config never saw this key at
        // all) as enabled; any explicitly-fetched value is trusted as-is.
        if value.source == .static {
            return true
        }
        return value.boolValue
    }
}
```

- [ ] **Step 3: Add `contributionsEnabled` to `CommunityModel`**

In `NeonCompass/Features/Community/CommunityModel.swift`, add a stored property and a gate provider dependency, following the existing constructor-injection pattern:

```swift
    private(set) var contributionsEnabled = true
    private let gateProvider: CommunityGateProviding
```

Update `init` to accept `gateProvider: CommunityGateProviding` as a new parameter (add it after `functions`, before `modelContext`, to match the plan's existing ordering — repository, functions, gateProvider, modelContext) and store it. Add a new method:

```swift
    func refreshContributionsEnabled() async {
        contributionsEnabled = (try? await gateProvider.isEnabled()) ?? true
    }
```

This changes `CommunityModel`'s initializer signature — update BOTH existing call sites (`MapScreen.swift`'s `loadModel()` and `ProfileScreen.swift`'s `.task`) to pass `gateProvider: RemoteConfigCommunityGateProvider()`, and update `NeonCompassTests/Community/CommunityFakesTests.swift` — it needs a `FakeCommunityGateProvider: CommunityGateProviding` fake (return `true` by default) passed into every `CommunityModel(...)` construction in that test file. Read the current test file before editing to match its existing fake style exactly.

- [ ] **Step 4: Gate the "Propose a spot" menu option in `MapScreen.swift`**

In `loadModel()`, after constructing `communityModel`, add a call to load the gate state alongside the existing `loadApprovedSpots()` call inside the same `Task`:

```swift
        Task {
            try? await contentStore.syncIfNeeded()
            model?.updatePOIs(contentStore.items)
            await communityModel?.loadApprovedSpots()
            await communityModel?.refreshContributionsEnabled()
        }
```

In the `.confirmationDialog`'s "Propose a spot" button, add a check: only offer the button conditionally — read the current confirmationDialog block (from Plan 5b, fixed in Task 6's review cycle) and wrap the button in an `if communityModel?.contributionsEnabled != false` (defaults to showing the button if `communityModel` itself is nil/not yet loaded, since Firebase-unavailable already handles that path separately — treat "not yet know" the same as "enabled" to avoid a flash of a missing option, consistent with this task's fail-open philosophy):

```swift
            if communityModel?.contributionsEnabled != false {
                Button("map.longPress.proposeSpot") {
                    if authModel.userID != nil {
                        pendingContributionLocation = pendingPinLocation
                    }
                    pendingPinLocation = nil
                }
            }
```

- [ ] **Step 5: Add the one new Localizable.xcstrings entry (if you added user-facing copy)**

This task's UI change is a conditional button *absence*, not new copy — no new Localizable.xcstrings key is needed unless you choose to show an explanatory message when contributions are disabled. Do not add one; a silently-absent menu option is sufficient for v1 (this mirrors the plan's existing "propose a spot while signed out silently no-ops" acceptance in Plan 5b).

- [ ] **Step 6: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`, including the updated `CommunityFakesTests` (constructor signature change must not break existing assertions — update call sites, don't change what's being tested).

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Core/Community/CommunityGateProviding.swift NeonCompass/Core/Community/RemoteConfigCommunityGateProvider.swift NeonCompass/Features/Community/CommunityModel.swift NeonCompass/Features/Map/MapScreen.swift NeonCompassTests/Community/CommunityFakesTests.swift NeonCompass/Features/Profile/ProfileScreen.swift
git commit -m "feat: Remote Config kill-switch for community contributions (client-side gate)"
```

---

## Self-Review

**Spec coverage:**
- App Check (App Attest) — Task 1. ✅ (code lands now; enforcement flip is a documented manual step gated on a device test, per this plan's explicit user decision).
- Cooldown, vocabulary filter, geo-dedup — Task 2. ✅
- Votes uniques by construction — already done in Plan 5b, unchanged here. ✅
- Monitoring de vélocité → priority review + shadow-ban, never auto-block — Task 3. ✅
- Filets: nothing public before moderation (unchanged from Plan 5b's rules), kill-switch — Task 5 (client) + Task 4 (CLI control), budget alerts — Task 1's ops doc (Console-only, not code). ✅
- Modération, <24h, votes as pre-filter, kill-switch if overwhelmed — Task 4 (the CLI surfaces flagged-first ordering as the "pre-filter" signal; the spec's <24h SLA is an operational commitment, not something code can enforce — noted, not silently dropped). ✅
- Level computed server-side, on approval AND on votes received — Task 3 (`xp.ts` + `castVote.ts` + Task 4's `approveContribution`). ✅
- Original synthwave grade names, never GTA ranks — `xp.ts`'s `GRADE_NAMES`, unit-tested against trademark tokens. ✅

**Known simplifications, not silently dropped:**
- Vote-driven XP is one-directional (no clawback on retraction/switch) — deliberate, documented in Task 3 Step 3, to avoid the complexity/gaming-surface of tracking historical vote state for XP purposes. If this becomes a problem in practice, it's a follow-up, not a defect in this plan.
- The banned-vocabulary list is intentionally minimal — first-pass filter only, human moderation (Task 4) is the actual backstop, matching how `handle.ts`'s word lists are treated in this codebase (small, curated, "extend by hand").
- Geo-dedup queries the full `approved` set of a category on every submission — acceptable at this content scale (a single schematic map, not a real-world geographic dataset); would need a spatial index if the collection grows to thousands of approved spots per category, which is far outside v1's expected scale.
- `flagSuspiciousContribution`'s shadow-ban escalation logic (flag once, shadow-ban on a second burst) is a specific, simple heuristic — the spec asks for "monitoring de vélocité" without prescribing an exact algorithm; this is a reasonable first implementation, tunable later without a schema change (both thresholds are named constants).
