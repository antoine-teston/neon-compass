# Comptes & Communauté — Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lay the account foundation for Plan 5 ("Comptes & communauté"): Sign in with Apple, an auto-generated synthwave handle, a server-computed profile (XP/level fields present but not yet incremented — nothing awards XP until the contribution system exists), and the two account-lifecycle Cloud Functions (`regenerateHandle`, `deleteAccount`) this plan's scope actually needs. This is infra-first, mirroring how Plan 3 split "sync infrastructure" from the features built on it — contribution submission, voting, moderation, and anti-abuse (velocity monitoring, shadow-ban, geo-dedup) are follow-on plans that build on what this one establishes, not part of it.

**Architecture:** Two new stacks meet here for the first time in this project: Swift client code (as always) and a Node.js/TypeScript Cloud Functions project (`functions/`), sharing the same Firebase project. Firebase Auth (Sign in with Apple provider) plus a `profiles` Firestore collection are the only new server-side surface; contributions/votes collections do not exist yet and are out of scope. Client writes to `profiles` never happen directly — Security Rules deny all direct writes to that collection, matching the spec's "single write path is Cloud Functions callable" rule; `createUserProfile` (an Auth `onCreate` trigger, not a callable) and `regenerateHandle`/`deleteAccount` (callables) are the only writers. Firebase behind `Core/` protocols is preserved: `Core/Auth/` gets an `AuthProviding` protocol (Sign in with Apple credential exchange) and a `ProfileRepository` protocol (reading the profile doc), each with a real Firebase-backed implementation and a fake for tests — mirroring the existing `Core/Content/` pattern exactly.

**Tech Stack:** Cloud Functions: Node.js 22, TypeScript, `firebase-functions` v2 (ESM, matching this repo's existing `tools/*` convention of `"type": "module"`), region `europe-west1` per spec. Swift: `AuthenticationServices` (Sign in with Apple UI), `FirebaseAuth`, `FirebaseFunctions` (new SPM dependencies), `@Observable`/`@MainActor`, Swift Testing.

## Scope

**In scope:** Sign-in/sign-out with Apple, auto-generated regenerable handle, a profile doc with placeholder `xp`/`level`/`isPremium` fields (present in the schema, not yet written to by anything since nothing awards XP yet), account deletion (Auth user + profile doc — cascading anonymization of *approved contributions* is explicitly deferred, see below), and fixing a real latent bug found while reading `firestore.rules` for this plan: the `guides`, `news`, and `trophies` collections have no explicit read rule today and silently fall through to the deny-all catch-all, meaning their Firestore sync would fail in production the moment real content is published to them (this was never caught earlier because nothing has been deployed to those collections yet).

**Explicitly out of scope, deferred to follow-on plans:**
- **Contribution submission + voting** (`submitContribution`/`castVote` Cloud Functions, the long-press-to-propose-a-spot map UI, `pending`/`approved` status, vote documents) — needs its own plan; `deleteAccount` in this plan only deletes the Auth user and profile doc because there is nothing else to cascade into yet. When the contribution system is built, `deleteAccount` will need revisiting to anonymize approved contributions instead of leaving them orphaned — flagged in that future plan, not solved here.
- **Anti-abuse** (App Check enforcement on Functions, velocity monitoring, geo-dedup, shadow-ban, cooldown) — meaningless without contributions to abuse; deferred with that system.
- **Moderation workflow** — same reason.
- **XP/leveling calculation, grades, badges** — the profile schema reserves the fields; nothing computes them yet, since XP is earned "par contribution approuvée et par vote reçu" (spec §5), neither of which exists yet.
- **App Check** itself is not wired up in this plan (it requires a real device + Apple Developer Program App Attest entitlement to test at all, and is only genuinely load-bearing once there's a write path worth protecting — the contribution system). Flagged as required before the contribution-system plan ships, not before this one.

**External prerequisites — the user must complete these, an agent cannot:**
1. **Apple Developer Program enrollment + Sign in with Apple configuration**: enable "Sign in with Apple" capability for the app's bundle ID in the Apple Developer portal, then configure the corresponding Services ID and key in Firebase Console's Authentication → Sign-in method → Apple provider. Without this, `FirebaseAuthProvider`'s real Apple credential exchange cannot succeed against the live Firebase project — but it compiles and its logic is unit-testable against fakes regardless (Task 4-5).
2. **Firebase Blaze plan** (pay-as-you-go billing) is required to *deploy* Cloud Functions to the real project — NOT required to write, unit-test, or run them locally via the **Firebase Emulator Suite** (free, works on the Spark/free plan). This plan's tasks all verify against the emulator; the final real deployment (Task 3's last step) is called out as a deliberately separate, user-triggered action, exactly like `content-cli publish`'s `FIREBASE_SERVICE_ACCOUNT_PATH` step earlier in this project.
3. **Real device testing** for the Sign in with Apple button itself: the simulator can render the button but a full end-to-end credential flow needs a real device with a valid provisioning profile. Flagged in Task 6, not blocking the rest of the plan.

## Global Constraints

- Firebase stays behind `Core/` protocols on the Swift side — features never import `FirebaseAuth`/`FirebaseFunctions` directly. `Core/Auth/FirebaseAuthProvider.swift` and `Core/Auth/FirebaseAccountFunctions.swift` are the only files that do.
- Cloud Functions region: `europe-west1` (spec §"Composants" — eur3/europe-west1 posture RGPD).
- No direct client writes to `profiles` — Security Rules deny all writes to that collection; only Cloud Functions (via the Admin SDK, which bypasses rules) write it.
- Handles are auto-generated only, never user-chosen free text (spec: "jamais de pseudo libre" — avoids name moderation, impersonation risk, and personal data collection).
- `xp`/`level`/`isPremium` fields exist in the profile schema now so later plans don't need a schema migration, but nothing in this plan computes or increments them — they are written once at creation (`xp: 0, level: 0, isPremium: false`) and never touched again by any code in this plan.
- Swift 6 strict concurrency; SwiftUI + `@Observable` only; Swift Testing for new Swift tests.
- TypeScript strict mode for Cloud Functions; Node's built-in test runner (`node --test`) for Cloud Functions unit tests — no new test framework dependency, matching this repo's existing minimal-dependency convention in `tools/*`.

---

### Task 1: Cloud Functions scaffolding + Firestore Security Rules

**Files:**
- Create: `functions/package.json`
- Create: `functions/tsconfig.json`
- Create: `functions/src/index.ts`
- Create: `firebase.json`
- Create: `.firebaserc`
- Modify: `firestore.rules`

**Interfaces:**
- Produces: an empty-but-real Cloud Functions project (`functions/src/index.ts` exports nothing yet — Task 2 adds the first real function), a working local emulator setup, and corrected Security Rules covering all five content collections (`poi`, `cheats`, `guides`, `news`, `trophies` — all public-read, deny-write, matching the existing `poi`/`cheats` pattern) plus a new `profiles/{uid}` rule (read: only the signed-in owner; write: deny always, since only Cloud Functions write it via the Admin SDK).

- [ ] **Step 1: Scaffold the Cloud Functions project**

Create `functions/package.json`:

```json
{
  "name": "functions",
  "version": "1.0.0",
  "description": "Neon Compass Cloud Functions — account lifecycle (Sign in with Apple profile, handle regeneration, account deletion). Contribution/voting/moderation functions are a future plan, not here.",
  "type": "module",
  "main": "lib/index.js",
  "engines": {
    "node": "22"
  },
  "scripts": {
    "build": "tsc",
    "test": "npm run build && node --test lib/**/*.test.js",
    "serve": "npm run build && firebase emulators:start --only functions,firestore,auth"
  },
  "dependencies": {
    "firebase-admin": "^13.0.0",
    "firebase-functions": "^6.0.0"
  },
  "devDependencies": {
    "typescript": "^5.6.0",
    "firebase-tools": "^13.0.0"
  }
}
```

Create `functions/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "lib",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "sourceMap": true
  },
  "include": ["src/**/*.ts"]
}
```

Create `functions/src/index.ts`:

```typescript
// Neon Compass Cloud Functions — account lifecycle only (Plan 5 infra).
// submitContribution/castVote/moderation are a future plan, not here.
export {};
```

- [ ] **Step 2: Install dependencies**

Run: `cd functions && npm install`
Expected: `node_modules/` created (already covered by the repo's root `.gitignore` pattern for `node_modules` used by `tools/*` — verify with `git status` that nothing under `functions/node_modules` gets staged).

- [ ] **Step 3: Configure Firebase project files**

Create `firebase.json` at the repo root:

```json
{
  "firestore": {
    "rules": "firestore.rules"
  },
  "functions": [
    {
      "source": "functions",
      "codebase": "default",
      "runtime": "nodejs22"
    }
  ],
  "emulators": {
    "functions": {
      "port": 5001
    },
    "firestore": {
      "port": 8080
    },
    "auth": {
      "port": 9099
    },
    "ui": {
      "enabled": true
    }
  }
}
```

Create `.firebaserc` at the repo root (project ID confirmed from this project's existing Firebase setup):

```json
{
  "projects": {
    "default": "neoncompass-gt-vi"
  }
}
```

- [ ] **Step 4: Fix the Security Rules gap and add the `profiles` collection**

Read the current `firestore.rules` first — it explicitly allows public read on `poi` and `cheats` only, with a catch-all `deny` for everything else (including `guides`/`news`/`trophies`, which have been silently unreadable in production since their respective plans, since nothing was ever deployed to them). Replace the full file with:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /poi/{document=**} {
      allow read: if true;
      allow write: if false;
    }
    match /cheats/{document=**} {
      allow read: if true;
      allow write: if false;
    }
    match /guides/{document=**} {
      allow read: if true;
      allow write: if false;
    }
    match /news/{document=**} {
      allow read: if true;
      allow write: if false;
    }
    match /trophies/{document=**} {
      allow read: if true;
      allow write: if false;
    }
    match /profiles/{uid} {
      allow read: if request.auth != null && request.auth.uid == uid;
      allow write: if false;
    }
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

- [ ] **Step 5: Verify the emulator starts and serves the rules**

Run: `firebase emulators:start --only firestore --project neoncompass-gt-vi` (from the repo root; requires `functions/node_modules/.bin/firebase` or a local `npx firebase-tools` — use `cd functions && npx firebase-tools emulators:start --only firestore --project neoncompass-gt-vi --config ../firebase.json` if the root has no `node_modules`)
Expected: emulator starts, logs `✔  firestore: Firestore Emulator UI websocket is running`, no rules-compilation error. Stop it with Ctrl-C once confirmed.

- [ ] **Step 6: Commit**

```bash
git add functions/package.json functions/tsconfig.json functions/src/index.ts firebase.json .firebaserc firestore.rules
git commit -m "feat: Cloud Functions scaffolding + fix guides/news/trophies read rule gap, add profiles collection rules"
```

---

### Task 2: `createUserProfile` — Auth trigger, synthwave handle generator

**Files:**
- Create: `functions/src/handle.ts`
- Create: `functions/src/handle.test.ts`
- Create: `functions/src/createUserProfile.ts`
- Modify: `functions/src/index.ts`

**Interfaces:**
- Produces: `generateHandle(): string` (pure function, e.g. `"NEON-FALCON-88"` — a synthwave adjective/noun pair plus a 2-digit number, no external dependency, no randomness source injected since Node's `crypto.randomInt` is fine to call directly here — this is server infra, not something a Swift test needs to fake), `createUserProfile` — a Firebase Auth `onCreate` blocking/background trigger (`beforeCreate` is not needed; a plain `functions.auth.user().onCreate` background trigger is sufent since nothing needs to block sign-in on profile creation) that writes `profiles/{uid}` with `{ handle: generateHandle(), xp: 0, level: 0, isPremium: false, createdAt: <server timestamp> }`.

- [ ] **Step 1: Write the failing test for the handle generator**

Create `functions/src/handle.test.ts`:

```typescript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateHandle } from './handle.js';

test('generateHandle produces an UPPER-UPPER-NN synthwave handle', () => {
  const handle = generateHandle();
  assert.match(handle, /^[A-Z]+-[A-Z]+-\d{2}$/);
});

test('generateHandle never emits a Rockstar/GTA trademark token', () => {
  const forbidden = /GTA|ROCKSTAR|VICE CITY|LEONIDA/i;
  for (let i = 0; i < 50; i++) {
    assert.doesNotMatch(generateHandle(), forbidden);
  }
});

test('generateHandle produces variety across repeated calls', () => {
  const samples = new Set(Array.from({ length: 20 }, () => generateHandle()));
  assert.ok(samples.size > 1, 'expected more than one distinct handle across 20 calls');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions && npm test`
Expected: FAIL — `./handle.js` does not exist yet (module not found).

- [ ] **Step 3: Write the handle generator**

Create `functions/src/handle.ts`:

```typescript
import { randomInt } from 'node:crypto';

// Synthwave-themed word lists — original, never a Rockstar/GTA term.
// Deliberately small and curated (not sourced from any wordlist that could
// leak trademarked names) — extend by hand if variety needs grow.
const ADJECTIVES = ['NEON', 'CHROME', 'RETRO', 'ULTRA', 'MIDNIGHT', 'ELECTRIC', 'TURBO', 'CRIMSON'];
const NOUNS = ['FALCON', 'MIRAGE', 'DRIFTER', 'HORIZON', 'CIRCUIT', 'PANTHER', 'VORTEX', 'RUNNER'];

export function generateHandle(): string {
  const adjective = ADJECTIVES[randomInt(ADJECTIVES.length)];
  const noun = NOUNS[randomInt(NOUNS.length)];
  const number = randomInt(100).toString().padStart(2, '0');
  return `${adjective}-${noun}-${number}`;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd functions && npm test`
Expected: all 3 tests pass.

- [ ] **Step 5: Write the Auth trigger**

Create `functions/src/createUserProfile.ts`:

```typescript
import { onCreate } from 'firebase-functions/v1/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { generateHandle } from './handle.js';

// Runs once per new Firebase Auth user (Sign in with Apple, in this app's
// case — no other provider is offered). Writes the initial profile doc;
// xp/level/isPremium are reserved fields for future plans (contribution
// system, StoreKit) and are never touched by anything else in this plan.
export const createUserProfile = onCreate(async (user) => {
  const db = getFirestore();
  await db.doc(`profiles/${user.uid}`).set({
    handle: generateHandle(),
    xp: 0,
    level: 0,
    isPremium: false,
    createdAt: FieldValue.serverTimestamp(),
  });
});
```

- [ ] **Step 6: Wire the trigger into the functions entry point**

Replace `functions/src/index.ts`:

```typescript
// Neon Compass Cloud Functions — account lifecycle only (Plan 5 infra).
// submitContribution/castVote/moderation are a future plan, not here.
export { createUserProfile } from './createUserProfile.js';
```

- [ ] **Step 7: Build to verify it compiles**

Run: `cd functions && npm run build`
Expected: `lib/index.js`, `lib/createUserProfile.js`, `lib/handle.js` produced, no TypeScript errors.

- [ ] **Step 8: Commit**

```bash
git add functions/src/handle.ts functions/src/handle.test.ts functions/src/createUserProfile.ts functions/src/index.ts
git commit -m "feat: createUserProfile Auth trigger + synthwave handle generator"
```

---

### Task 3: `regenerateHandle` + `deleteAccount` callables

**Files:**
- Create: `functions/src/regenerateHandle.ts`
- Create: `functions/src/deleteAccount.ts`
- Modify: `functions/src/index.ts`

**Interfaces:**
- Consumes: `generateHandle()` (Task 2).
- Produces: `regenerateHandle` — an `onCall` callable, requires `request.auth` (throws `unauthenticated` otherwise), overwrites the caller's own `profiles/{uid}.handle` with a fresh `generateHandle()` value, returns the new handle. `deleteAccount` — an `onCall` callable, requires `request.auth`, deletes `profiles/{uid}` and the Firebase Auth user itself (in that order — profile doc first, since deleting the Auth user first would make a retry after a failed profile-delete impossible to attribute to a uid). Both callables are region-pinned to `europe-west1` per the plan's Global Constraints.

- [ ] **Step 1: Write `regenerateHandle`**

Create `functions/src/regenerateHandle.ts`:

```typescript
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { generateHandle } from './handle.js';

export const regenerateHandle = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const newHandle = generateHandle();
  await getFirestore().doc(`profiles/${request.auth.uid}`).update({ handle: newHandle });
  return { handle: newHandle };
});
```

- [ ] **Step 2: Write `deleteAccount`**

Create `functions/src/deleteAccount.ts`:

```typescript
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

// Scope note (Plan 5 infra): only the profile doc and the Auth user itself
// are deleted here. There are no contribution/vote documents yet — when
// that system exists, this function must be revisited to anonymize
// approved contributions instead of leaving them referencing a deleted uid
// (spec: "anonymisée, jamais effacée" for approved contributions).
export const deleteAccount = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;
  await getFirestore().doc(`profiles/${uid}`).delete();
  await getAuth().deleteUser(uid);
  return { deleted: true };
});
```

- [ ] **Step 3: Wire both callables into the functions entry point**

Replace `functions/src/index.ts`:

```typescript
// Neon Compass Cloud Functions — account lifecycle only (Plan 5 infra).
// submitContribution/castVote/moderation are a future plan, not here.
export { createUserProfile } from './createUserProfile.js';
export { regenerateHandle } from './regenerateHandle.js';
export { deleteAccount } from './deleteAccount.js';
```

- [ ] **Step 4: Build to verify it compiles**

Run: `cd functions && npm run build`
Expected: no TypeScript errors, `lib/regenerateHandle.js` and `lib/deleteAccount.js` produced.

- [ ] **Step 5: Verify against the emulator manually**

Run: `cd functions && npm run serve` (starts the Functions + Firestore + Auth emulators together)
In another terminal, use the Emulator UI (printed URL, typically `http://127.0.0.1:4000`) to: create a test Auth user via the Auth emulator tab (triggers `createUserProfile` — confirm a `profiles/{uid}` doc appears in the Firestore emulator tab with a handle matching `ADJECTIVE-NOUN-NN`), then call `regenerateHandle`/`deleteAccount` via the Functions emulator's shell (`firebase functions:shell` or an authenticated `curl` against the emulator's callable HTTP endpoint) and confirm the doc updates/disappears accordingly. Stop the emulator with Ctrl-C when done. This step has no automated assertion — it's a manual integration smoke test of the three functions working together against a real (emulated) Firestore + Auth, which `node --test` alone cannot exercise (Auth triggers need the Auth emulator running, not just a Firestore instance).

- [ ] **Step 6: Commit**

```bash
git add functions/src/regenerateHandle.ts functions/src/deleteAccount.ts functions/src/index.ts
git commit -m "feat: regenerateHandle + deleteAccount callables (europe-west1)"
```

---

### Task 4: Swift `Core/Auth/` — protocols, Firebase-backed implementations, SPM dependencies

**Files:**
- Modify: `project.yml`
- Create: `NeonCompass/NeonCompass.entitlements`
- Create: `NeonCompass/Core/Auth/AuthProviding.swift`
- Create: `NeonCompass/Core/Auth/FirebaseAuthProvider.swift`
- Create: `NeonCompass/Core/Auth/Profile.swift`
- Create: `NeonCompass/Core/Auth/ProfileRepository.swift`
- Create: `NeonCompass/Core/Auth/FirestoreProfileRepository.swift`
- Create: `NeonCompass/Core/Auth/AccountFunctionsCalling.swift`
- Create: `NeonCompass/Core/Auth/FirebaseAccountFunctions.swift`

**Interfaces:**
- Produces: `AuthProviding` (`var currentUserID: String? { get }`, `func signIn(idTokenString: String, nonce: String) async throws -> String`, `func signOut() throws`), `FirebaseAuthProvider: AuthProviding` (wraps `FirebaseAuth.Auth`, builds an `OAuthProvider.credential(providerID: .apple, ...)`), `Profile` (`handle: String`, `xp: Int`, `level: Int`, `isPremium: Bool`, `Codable, Equatable, Sendable` — decoded directly from the Firestore document, no `LocalizedText` involved since none of these fields are user-facing translated content), `ProfileRepository` (`func fetchProfile(uid: String) async throws -> Profile?`), `FirestoreProfileRepository: ProfileRepository`, `AccountFunctionsCalling` (`func regenerateHandle() async throws -> String`, `func deleteAccount() async throws`), `FirebaseAccountFunctions: AccountFunctionsCalling` (wraps `Functions.functions(region: "europe-west1")`).

- [ ] **Step 1: Add `FirebaseAuth` and `FirebaseFunctions` SPM dependencies**

In `project.yml`, under `targets.NeonCompass.dependencies`, change:

```yaml
    dependencies:
      - package: Firebase
        product: FirebaseCore
      - package: Firebase
        product: FirebaseFirestore
      - package: Firebase
        product: FirebaseRemoteConfig
```

to:

```yaml
    dependencies:
      - package: Firebase
        product: FirebaseCore
      - package: Firebase
        product: FirebaseFirestore
      - package: Firebase
        product: FirebaseRemoteConfig
      - package: Firebase
        product: FirebaseAuth
      - package: Firebase
        product: FirebaseFunctions
```

- [ ] **Step 2: Add the Sign in with Apple entitlement**

Create `NeonCompass/NeonCompass.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
</dict>
</plist>
```

In `project.yml`, add an `entitlements` key to the `NeonCompass` target's `settings.base` (create `settings` under the target if it doesn't already have one at the target level — the existing `settings.base` block at the top of the file is global, this is a target-specific addition):

```yaml
  NeonCompass:
    type: application
    platform: iOS
    settings:
      base:
        CODE_SIGN_ENTITLEMENTS: NeonCompass/NeonCompass.entitlements
    sources:
```

(Insert the `settings` block between `platform: iOS` and the existing `sources:` line — do not duplicate or remove the existing `sources`/`dependencies` keys.)

- [ ] **Step 3: Write `AuthProviding` and `FirebaseAuthProvider`**

Create `NeonCompass/Core/Auth/AuthProviding.swift`:

```swift
import Foundation

/// Abstraction sur Firebase Auth — Sign in with Apple est le seul
/// fournisseur proposé (spec §3 : "seule option de connexion proposée").
protocol AuthProviding: Sendable {
    var currentUserID: String? { get }
    func signIn(idTokenString: String, nonce: String) async throws -> String
    func signOut() throws
}
```

Create `NeonCompass/Core/Auth/FirebaseAuthProvider.swift`:

```swift
@preconcurrency import FirebaseAuth

/// Implémentation réelle de AuthProviding. Ne référence jamais
/// FirebaseApp.configure() — la configuration de l'app reste centralisée
/// au niveau App.
final class FirebaseAuthProvider: AuthProviding {
    nonisolated(unsafe) private let auth: Auth

    init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }

    var currentUserID: String? {
        auth.currentUser?.uid
    }

    func signIn(idTokenString: String, nonce: String) async throws -> String {
        let credential = OAuthProvider.credential(providerID: .apple, idToken: idTokenString, rawNonce: nonce)
        let result = try await auth.signIn(with: credential)
        return result.user.uid
    }

    func signOut() throws {
        try auth.signOut()
    }
}
```

- [ ] **Step 4: Write `Profile`, `ProfileRepository`, `FirestoreProfileRepository`**

Create `NeonCompass/Core/Auth/Profile.swift`:

```swift
import Foundation

/// Miroir du document `profiles/{uid}` écrit par la Cloud Function
/// `createUserProfile` — jamais écrit directement par le client (Security
/// Rules : write toujours refusé sur cette collection).
struct Profile: Codable, Equatable, Sendable {
    let handle: String
    let xp: Int
    let level: Int
    let isPremium: Bool
}
```

Create `NeonCompass/Core/Auth/ProfileRepository.swift`:

```swift
import Foundation

protocol ProfileRepository: Sendable {
    func fetchProfile(uid: String) async throws -> Profile?
}
```

Create `NeonCompass/Core/Auth/FirestoreProfileRepository.swift`:

```swift
import FirebaseFirestore

/// Implémentation réelle de ProfileRepository. Le document peut ne pas
/// encore exister juste après le sign-in (la Cloud Function createUserProfile
/// tourne de façon asynchrone sur l'événement de création du user Auth) —
/// retourner nil dans ce cas plutôt que de faire échouer l'appelant.
final class FirestoreProfileRepository: ProfileRepository {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func fetchProfile(uid: String) async throws -> Profile? {
        let document = try await firestore.collection("profiles").document(uid).getDocument()
        guard document.exists, let data = document.data() else { return nil }
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(Profile.self, from: json)
    }
}
```

- [ ] **Step 5: Write `AccountFunctionsCalling` and `FirebaseAccountFunctions`**

Create `NeonCompass/Core/Auth/AccountFunctionsCalling.swift`:

```swift
import Foundation

protocol AccountFunctionsCalling: Sendable {
    func regenerateHandle() async throws -> String
    func deleteAccount() async throws
}
```

Create `NeonCompass/Core/Auth/FirebaseAccountFunctions.swift`:

```swift
@preconcurrency import FirebaseFunctions

/// Implémentation réelle de AccountFunctionsCalling, région europe-west1
/// (miroir de functions/src/regenerateHandle.ts / deleteAccount.ts).
final class FirebaseAccountFunctions: AccountFunctionsCalling {
    nonisolated(unsafe) private let functions: Functions

    init(functions: Functions = Functions.functions(region: "europe-west1")) {
        self.functions = functions
    }

    func regenerateHandle() async throws -> String {
        let result = try await functions.httpsCallable("regenerateHandle").call()
        guard let data = result.data as? [String: Any], let handle = data["handle"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return handle
    }

    func deleteAccount() async throws {
        _ = try await functions.httpsCallable("deleteAccount").call()
    }
}
```

- [ ] **Step 6: Build to verify everything compiles**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **` (nothing references these new types yet outside themselves, so this only verifies they compile — `xcodegen generate` must run first to pick up `project.yml`'s new dependencies/entitlements, which `Scripts/build.sh` already does as its first step).

- [ ] **Step 7: Commit**

```bash
git add project.yml NeonCompass/NeonCompass.entitlements NeonCompass/Core/Auth/
git commit -m "feat: Core/Auth protocols + Firebase-backed implementations (Sign in with Apple, profile, account functions)"
```

---

### Task 5: `AuthModel` + `ProfileModel`

**Files:**
- Create: `NeonCompass/Features/Profile/AuthModel.swift`
- Create: `NeonCompass/Features/Profile/ProfileModel.swift`
- Test: `NeonCompassTests/Profile/AuthModelTests.swift`
- Test: `NeonCompassTests/Profile/ProfileModelTests.swift`
- Test: `NeonCompassTests/Profile/FakesTests.swift` (new file — mirrors the `Core/Content/` fakes convention, but for auth/profile)

**Interfaces:**
- Consumes: `AuthProviding`, `ProfileRepository`, `AccountFunctionsCalling`, `Profile` (Task 4).
- Produces: `AuthModel` (`@Observable @MainActor`, `init(authProvider: AuthProviding)`, `private(set) var userID: String?`, `func signIn(idTokenString: String, nonce: String) async throws`, `func signOut() throws`), `ProfileModel` (`@Observable @MainActor`, `init(repository: ProfileRepository, functions: AccountFunctionsCalling)`, `private(set) var profile: Profile?`, `func loadProfile(uid: String) async`, `func regenerateHandle() async throws`, `func deleteAccount() async throws`).

- [ ] **Step 1: Write the fakes**

Create `NeonCompassTests/Profile/FakesTests.swift`:

```swift
import Testing
@testable import NeonCompass

final class FakeAuthProvider: AuthProviding {
    nonisolated(unsafe) var userIDToReturn: String?
    nonisolated(unsafe) private(set) var signOutCallCount = 0

    var currentUserID: String? { userIDToReturn }

    func signIn(idTokenString: String, nonce: String) async throws -> String {
        let uid = "fake-uid"
        userIDToReturn = uid
        return uid
    }

    func signOut() throws {
        signOutCallCount += 1
        userIDToReturn = nil
    }
}

final class FakeProfileRepository: ProfileRepository {
    nonisolated(unsafe) var profileToReturn: Profile?

    func fetchProfile(uid: String) async throws -> Profile? {
        profileToReturn
    }
}

final class FakeAccountFunctions: AccountFunctionsCalling {
    nonisolated(unsafe) var handleToReturn = "NEON-FALCON-88"
    nonisolated(unsafe) private(set) var deleteAccountCallCount = 0

    func regenerateHandle() async throws -> String {
        handleToReturn
    }

    func deleteAccount() async throws {
        deleteAccountCallCount += 1
    }
}

struct FakesTests {
    @Test func authProviderTracksSignOutCalls() throws {
        let fake = FakeAuthProvider()
        fake.userIDToReturn = "existing-uid"
        try fake.signOut()
        #expect(fake.signOutCallCount == 1)
        #expect(fake.currentUserID == nil)
    }
}
```

- [ ] **Step 2: Write the failing tests for `AuthModel`**

Create `NeonCompassTests/Profile/AuthModelTests.swift`:

```swift
import Testing
@testable import NeonCompass

@MainActor
struct AuthModelTests {
    @Test func startsSignedOutWhenNoCurrentUser() {
        let model = AuthModel(authProvider: FakeAuthProvider())
        #expect(model.userID == nil)
    }

    @Test func startsSignedInWhenAuthProviderHasACurrentUser() {
        let provider = FakeAuthProvider()
        provider.userIDToReturn = "existing-uid"
        let model = AuthModel(authProvider: provider)
        #expect(model.userID == "existing-uid")
    }

    @Test func signInSetsUserID() async throws {
        let model = AuthModel(authProvider: FakeAuthProvider())
        try await model.signIn(idTokenString: "token", nonce: "nonce")
        #expect(model.userID == "fake-uid")
    }

    @Test func signOutClearsUserID() async throws {
        let model = AuthModel(authProvider: FakeAuthProvider())
        try await model.signIn(idTokenString: "token", nonce: "nonce")
        try model.signOut()
        #expect(model.userID == nil)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `Scripts/test.sh`
Expected: FAIL — `AuthModel` does not exist yet (compile error).

- [ ] **Step 4: Write `AuthModel`**

Create `NeonCompass/Features/Profile/AuthModel.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AuthModel {
    private(set) var userID: String?

    private let authProvider: AuthProviding

    init(authProvider: AuthProviding) {
        self.authProvider = authProvider
        self.userID = authProvider.currentUserID
    }

    func signIn(idTokenString: String, nonce: String) async throws {
        userID = try await authProvider.signIn(idTokenString: idTokenString, nonce: nonce)
    }

    func signOut() throws {
        try authProvider.signOut()
        userID = nil
    }
}
```

- [ ] **Step 5: Run tests to verify `AuthModel`'s tests pass**

Run: `Scripts/test.sh`
Expected: the four `AuthModelTests` tests pass (`ProfileModel` doesn't exist yet, so overall suite still fails at this point — continue to the next step).

- [ ] **Step 6: Write the failing tests for `ProfileModel`**

Create `NeonCompassTests/Profile/ProfileModelTests.swift`:

```swift
import Testing
@testable import NeonCompass

@MainActor
struct ProfileModelTests {
    @Test func loadProfileFetchesAndStoresTheProfile() async {
        let repository = FakeProfileRepository()
        repository.profileToReturn = Profile(handle: "NEON-FALCON-88", xp: 0, level: 0, isPremium: false)
        let model = ProfileModel(repository: repository, functions: FakeAccountFunctions())
        await model.loadProfile(uid: "some-uid")
        #expect(model.profile?.handle == "NEON-FALCON-88")
    }

    @Test func loadProfileLeavesProfileNilWhenNotYetCreated() async {
        let model = ProfileModel(repository: FakeProfileRepository(), functions: FakeAccountFunctions())
        await model.loadProfile(uid: "some-uid")
        #expect(model.profile == nil)
    }

    @Test func regenerateHandleUpdatesTheStoredProfile() async throws {
        let repository = FakeProfileRepository()
        repository.profileToReturn = Profile(handle: "NEON-FALCON-88", xp: 0, level: 0, isPremium: false)
        let functions = FakeAccountFunctions()
        functions.handleToReturn = "CHROME-MIRAGE-42"
        let model = ProfileModel(repository: repository, functions: functions)
        await model.loadProfile(uid: "some-uid")

        try await model.regenerateHandle()

        #expect(model.profile?.handle == "CHROME-MIRAGE-42")
    }

    @Test func deleteAccountCallsTheFunctionExactlyOnce() async throws {
        let functions = FakeAccountFunctions()
        let model = ProfileModel(repository: FakeProfileRepository(), functions: functions)
        try await model.deleteAccount()
        #expect(functions.deleteAccountCallCount == 1)
    }
}
```

- [ ] **Step 7: Run tests to verify they fail**

Run: `Scripts/test.sh`
Expected: FAIL — `ProfileModel` does not exist yet (compile error).

- [ ] **Step 8: Write `ProfileModel`**

Create `NeonCompass/Features/Profile/ProfileModel.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class ProfileModel {
    private(set) var profile: Profile?

    private let repository: ProfileRepository
    private let functions: AccountFunctionsCalling

    init(repository: ProfileRepository, functions: AccountFunctionsCalling) {
        self.repository = repository
        self.functions = functions
    }

    func loadProfile(uid: String) async {
        profile = try? await repository.fetchProfile(uid: uid)
    }

    func regenerateHandle() async throws {
        let newHandle = try await functions.regenerateHandle()
        profile?.handle = newHandle
    }

    func deleteAccount() async throws {
        try await functions.deleteAccount()
    }
}
```

Note: `regenerateHandle()` mutates `profile?.handle` directly rather than re-fetching from `repository` — the Cloud Function already returns the new handle in its response, so a second round-trip read would be redundant. This requires `Profile.handle` to be a `var`, not `let` — go back and change `Profile.handle` from `let handle: String` to `var handle: String` in `NeonCompass/Core/Auth/Profile.swift` (Task 4's file) as part of this step; every other `Profile` field stays `let`, since nothing else in this plan mutates them in place.

- [ ] **Step 9: Run tests to verify they all pass**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including all `AuthModelTests`, `ProfileModelTests`, and the new `FakesTests` suite.

- [ ] **Step 10: Build the app**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 11: Commit**

```bash
git add NeonCompass/Features/Profile/AuthModel.swift NeonCompass/Features/Profile/ProfileModel.swift NeonCompass/Core/Auth/Profile.swift NeonCompassTests/Profile/
git commit -m "feat: AuthModel + ProfileModel (sign-in state, profile load, handle regeneration, account deletion)"
```

---

### Task 6: `ProfileScreen` — Sign in with Apple UI, wire into `RootView`

**Files:**
- Create: `NeonCompass/Features/Profile/ProfileScreen.swift`
- Modify: `NeonCompass/App/RootView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `AuthModel`, `ProfileModel` (Task 5), `FirebaseAuthProvider`, `FirestoreProfileRepository`, `FirebaseAccountFunctions` (Task 4).
- Produces: `ProfileScreen` — the `AppTab.profile` case's real screen, replacing `PlaceholderScreen(tab: .profile)`. Signed-out state shows a native `SignInWithAppleButton`; signed-in state shows the handle, a "Regenerate" button, "Sign out", and "Delete account" (with a confirmation alert — this is destructive and irreversible).

No dedicated model-level test beyond Task 5's (this task is view assembly + the platform-specific Sign in with Apple nonce/credential plumbing, which cannot be unit-tested without a real device — see the plan's Scope section). Verification is build + a manual note for whoever tests this on a real device later.

- [ ] **Step 1: Add the Profile screen's String Catalog keys**

In `Localizable.xcstrings`, add these keys following the existing structure:
- `profile.signIn.prompt` = "Sign in to save your progress across devices and contribute to the map."
- `profile.handle.regenerate` = "Regenerate handle"
- `profile.signOut` = "Sign out"
- `profile.deleteAccount` = "Delete account"
- `profile.deleteAccount.confirmTitle` = "Delete your account?"
- `profile.deleteAccount.confirmMessage` = "This permanently deletes your profile. This cannot be undone."
- `profile.deleteAccount.confirmButton` = "Delete"
- `profile.deleteAccount.cancelButton` = "Cancel"

- [ ] **Step 2: Write `ProfileScreen`**

Create `NeonCompass/Features/Profile/ProfileScreen.swift`:

```swift
import SwiftUI
import AuthenticationServices
import CryptoKit

struct ProfileScreen: View {
    @State private var authModel = AuthModel(authProvider: FirebaseAuthProvider())
    @State private var profileModel = ProfileModel(
        repository: FirestoreProfileRepository(),
        functions: FirebaseAccountFunctions()
    )
    @State private var currentNonce: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 24) {
                if let userID = authModel.userID {
                    signedInContent(userID: userID)
                } else {
                    signedOutContent
                }
            }
            .padding(24)
        }
        .task(id: authModel.userID) {
            if let userID = authModel.userID {
                await profileModel.loadProfile(uid: userID)
            }
        }
        .alert(
            "profile.deleteAccount.confirmTitle",
            isPresented: $showDeleteConfirmation
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) {}
            Button("profile.deleteAccount.confirmButton", role: .destructive) {
                Task {
                    try? await profileModel.deleteAccount()
                    try? authModel.signOut()
                }
            }
        } message: {
            Text("profile.deleteAccount.confirmMessage")
        }
    }

    private var signedOutContent: some View {
        VStack(spacing: 16) {
            Text("profile.signIn.prompt")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = []
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
        }
    }

    private func signedInContent(userID: String) -> some View {
        VStack(spacing: 16) {
            Text(profileModel.profile?.handle ?? "…")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)

            Button("profile.handle.regenerate") {
                Task { try? await profileModel.regenerateHandle() }
            }

            Button("profile.signOut") {
                try? authModel.signOut()
            }

            Button("profile.deleteAccount", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idTokenString = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            return
        }
        Task {
            try? await authModel.signIn(idTokenString: idTokenString, nonce: nonce)
        }
    }

    // Standard Firebase + Sign in with Apple boilerplate: a random nonce is
    // sent to Apple hashed (SHA256), and the raw nonce is sent to Firebase
    // alongside Apple's signed identity token — this round-trip is what lets
    // Firebase verify the token was issued for *this* sign-in attempt.
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 3: Wire `ProfileScreen` into `RootView`**

In `NeonCompass/App/RootView.swift`, the `screen(for:)` method currently reads (after Plan 4's change):

```swift
    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedScreen()
        case .map: MapScreen()
        case .cheats: CheatsScreen()
        case .progress: ProgressionScreen()
        default: PlaceholderScreen(tab: tab)
        }
    }
```

Change it to:

```swift
    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedScreen()
        case .map: MapScreen()
        case .cheats: CheatsScreen()
        case .progress: ProgressionScreen()
        case .profile: ProfileScreen()
        }
    }
```

(This removes the `default:` case entirely — `AppTab` now has a screen for every one of its 5 cases, so the switch is exhaustive without a fallback. If a 6th tab is ever added without a matching case here, this will be a compile error, which is correct — better than silently falling through to a placeholder.)

- [ ] **Step 4: Build and run the full test suite**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Profile/ProfileScreen.swift NeonCompass/App/RootView.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: wire ProfileScreen into the Profile tab (Sign in with Apple, handle, sign-out, delete account)"
```

---

## Self-Review

**Couverture spec (scope de ce plan)** : Sign in with Apple (seule option de connexion) ✓, handle auto-généré jamais un pseudo libre ✓, régénérable ✓, champs XP/niveau/premium réservés sans être calculés (rien ne les incrémente encore, honnête avec le spec — l'XP vient des contributions/votes, aucun des deux n'existe) ✓, suppression de compte in-app ✓ (cascade limitée à profil+Auth, anonymisation des contributions explicitement différée puisqu'aucune contribution n'existe), chemin d'écriture unique via Cloud Functions callable, jamais d'écriture client directe ✓, région europe-west1 ✓.

**Bug corrigé au passage** : `guides`/`news`/`trophies` n'avaient aucune règle de lecture explicite dans `firestore.rules` — repéré en lisant le fichier pour cette tâche, corrigé dans la même modification (Task 1) plutôt que d'ouvrir un plan à part pour trois lignes de règles.

**Cohérence des types** : `AuthProviding`/`ProfileRepository`/`AccountFunctionsCalling` (Task 4) réutilisés tels quels dans `AuthModel`/`ProfileModel` (Task 5) et `ProfileScreen` (Task 6). Les fonctions Cloud (Tasks 2-3) et leurs équivalents Swift (Task 4) partagent les mêmes noms de collection/fonction (`profiles`, `regenerateHandle`, `deleteAccount`) — aucun renommage en cours de route.

**Ce que ce plan ne fait pas (volontairement, cf. section Scope)** :
1. Contribution/vote (`submitContribution`/`castVote`, UI carte, statuts pending/approved) — plan dédié à venir.
2. Anti-abus (App Check enforcement, vélocité, shadow-ban, dédup géo, cooldown) — sans objet tant qu'il n'y a rien à abuser.
3. Modération — même raison.
4. Calcul XP/niveau/grades/badges — champs réservés, non calculés.
5. App Check côté client — nécessite un vrai appareil + entitlement, à câbler juste avant le système de contribution, pas ici.

**Prérequis externes signalés, pas contournés** : compte Apple Developer + config Firebase Console (Sign in with Apple), plan Blaze uniquement pour le déploiement réel (dev/test via l'émulateur, gratuit), test réel du bouton Sign in with Apple sur un vrai appareil.
