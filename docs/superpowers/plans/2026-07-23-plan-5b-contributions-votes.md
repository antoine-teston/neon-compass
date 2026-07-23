# Plan 5b — Contributions communautaires & votes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer la boucle de contribution communautaire de bout en bout côté écriture (soumettre un spot, voter, signaler) et côté lecture (afficher les spots approuvés sur la carte, mon historique de contributions, bloquer un contributeur) — sans les défenses anti-abus avancées ni la modération, qui forment le Plan 5c.

**Architecture:** Deux nouvelles Cloud Functions callable (`submitContribution`, `castVote`) qui écrivent dans `contributions`/`votes`, plus `reportContribution` pour le signalement (Apple 1.2). Nouvelle collection `reports`. Un nouveau `reportContribution`/vote/submit passent tous par des Cloud Functions — jamais d'écriture directe du client (Security Rules `write: if false` sur les trois collections). Côté Swift, un nouveau dossier `Core/Community/` mirrorant `Core/Auth/` (protocoles + implémentations Firebase), un `CommunityModel` `@Observable` pour la carte et le profil, et un blocage de contributeur strictement local (SwiftData, comme `PersonalPin`).

**Tech Stack:** Firebase Cloud Functions (Node 22, TypeScript, ESM, `firebase-functions` v6, région `europe-west1`), Firestore, SwiftUI + `@Observable`, SwiftData.

## Global Constraints

- **Jamais d'écriture client directe** sur `contributions`, `votes`, `reports` — Security Rules `allow write: if false` sur les trois, tout passe par Cloud Functions callable (spec §5).
- **Statuts contribution** : `pending` → `approved` | `rejected`. Rien de `pending`/`rejected` n'est visible publiquement — seul l'auteur peut lire ses propres documents quel que soit leur statut (Security Rules), tout le monde peut lire les documents `approved`.
- **Votes uniques par construction** : ID de document `votes/{spotId}_{uid}` — revoter écrase le même document, jamais un nouveau document (spec §"Anti-spam & anti-abus", point 4). Compteurs agrégés (`upvotes`/`downvotes`) uniquement mis à jour côté serveur, dans la même transaction que l'écriture du vote.
- **Pas de pseudo libre** : `authorHandle` est un instantané du handle synthwave auto-généré au moment de la soumission (jamais de texte libre d'identité).
- **Contenu contribution non traduit** : `title` est un champ texte libre unique (≤ 280 caractères) + `languageCode` (un des 5 : `en`/`fr`/`es`/`it`/`de`), affiché tel quel avec un tag de langue — jamais traduit en v1 (spec §"Contenu & traductions").
- **Suppression de compte — anonymisation, pas suppression, des contributions approuvées** : `deleteAccount` doit mettre `authorUid: null` et `authorHandle` à un jeton fixe sur les contributions `approved` de l'utilisateur (jamais les effacer), et effacer intégralement ses contributions `pending`/`rejected` (jamais rendues publiques) et tous ses documents `votes` (spec §"Droits & suppression").
- **Décodage Firestore** : toute lecture de document dans ce plan utilise `document.data(as:)` (Codable natif Firestore), jamais `JSONSerialization.data(withJSONObject:)` — cette dernière lève une exception Objective-C non rattrapable dès qu'un champ `Timestamp` est présent (bug corrigé au Plan 5 sur `FirestoreProfileRepository`, `contributions` a un champ `createdAt: Timestamp`, ce piège s'applique donc ici aussi).
- **Hors scope de ce plan (Plan 5c)** : App Check, cooldown de soumission, déduplication géographique, filtre de vocabulaire, monitoring de vélocité/shadow-ban, file de modération, calcul du niveau/XP côté serveur à l'approbation. `submitContribution` fait une validation d'entrée basique (schéma, longueurs, bornes) — ce n'est **pas** la couche anti-abus de la spec, qui reste entièrement à construire.
- **Firebase reste derrière des protocoles dans `Core/`** — les features (`Features/Map`, `Features/Profile`) n'importent jamais directement un SDK Firebase.
- **Swift 6, concurrence stricte.** Toute propriété de handle SDK Firebase sur une classe utilise `nonisolated(unsafe)` (précédent : `FirestoreProfileRepository`, `FirebaseAccountFunctions`).
- **Chaînes localisées** : toute nouvelle chaîne visible passe par `NeonCompass/Resources/Localizable.xcstrings`, `sourceLanguage: "en"` (la bascule FR-primaire n'est pas encore faite — ne pas y toucher dans ce plan).

---

## File Structure

```
functions/src/
  contribution.ts              # types partagés + validateSubmission() pure, testable
  submitContribution.ts        # Cloud Function callable
  vote.ts                      # applyVote() pure (delta de compteurs), testable
  castVote.ts                  # Cloud Function callable
  reportContribution.ts        # Cloud Function callable
  deleteAccount.ts             # MODIFIÉ : anonymise/efface contributions + votes
  index.ts                     # MODIFIÉ : exporte les 3 nouvelles functions

firestore.rules                # MODIFIÉ : contributions/, votes/, reports/

NeonCompass/Core/Community/
  Contribution.swift            # modèle domaine (pas de import Firebase)
  BlockedContributor.swift      # @Model SwiftData
  ContributionRepository.swift  # protocole
  FirestoreContributionRepository.swift
  ContributionFunctionsCalling.swift  # protocole + VoteDirection
  FirebaseContributionFunctions.swift

NeonCompass/Features/Community/
  CommunityModel.swift           # @Observable @MainActor
  ContributionSubmissionSheet.swift
  ContributionAnnotationView.swift   # pin "communauté" + détail + vote/signalement/blocage

NeonCompass/Features/Map/
  MapScreen.swift                # MODIFIÉ : menu appui-long, overlay spots communauté
NeonCompass/Features/Profile/
  ProfileScreen.swift            # MODIFIÉ : section "Mes contributions" + contributeurs bloqués

NeonCompass/App/NeonCompassApp.swift   # MODIFIÉ : .modelContainer ajoute BlockedContributor.self
NeonCompass/Resources/Localizable.xcstrings   # MODIFIÉ : nouvelles clés

functions/src/contribution.test.ts
functions/src/vote.test.ts
NeonCompassTests/Community/CommunityFakesTests.swift
```

---

### Task 1: Cloud Function `submitContribution`

**Files:**
- Create: `functions/src/contribution.ts`
- Create: `functions/src/contribution.test.ts`
- Create: `functions/src/submitContribution.ts`
- Modify: `functions/src/index.ts`

**Interfaces:**
- Produces: `validateSubmission(input: unknown): SubmissionInput` (throws `Error` with a descriptive message on any invalid field — the callable wrapper turns that into `HttpsError('invalid-argument', ...)`), `ALLOWED_CATEGORIES`, `ALLOWED_LANGUAGES`, exported `SubmissionInput` type `{ category: string; title: string; position: { x: number; y: number }; languageCode: string }`.
- Consumes: `generateHandle` is NOT used here — the author's *existing* handle is read from `profiles/{uid}` (written at sign-up by `createUserProfile`, Plan 5).

- [ ] **Step 1: Write `contribution.ts` (validation, no Firebase imports — pure and unit-testable)**

```typescript
// functions/src/contribution.ts
// Pure validation for submitContribution's input — kept separate from the
// onCall wrapper so it's unit-testable with plain node:test, no emulator
// needed. Mirrors handle.ts's pattern (pure function + separate CF file).

export const ALLOWED_CATEGORIES = ['landmark', 'collectible', 'activity', 'safehouse', 'vehicle', 'event'] as const;
export type ContributionCategory = (typeof ALLOWED_CATEGORIES)[number];

export const ALLOWED_LANGUAGES = ['en', 'fr', 'es', 'it', 'de'] as const;
export type ContributionLanguage = (typeof ALLOWED_LANGUAGES)[number];

export interface SubmissionInput {
  category: ContributionCategory;
  title: string;
  position: { x: number; y: number };
  languageCode: ContributionLanguage;
}

const MAX_TITLE_LENGTH = 280;

// Deliberately basic: schema/length/range validation only. The spec's full
// anti-abuse layer (App Check, cooldown, geo-dedup, vocabulary filter,
// velocity monitoring) is Plan 5c, not here — see this plan's Global
// Constraints.
export function validateSubmission(input: unknown): SubmissionInput {
  if (typeof input !== 'object' || input === null) {
    throw new Error('Submission must be an object.');
  }
  const record = input as Record<string, unknown>;

  const category = record.category;
  if (typeof category !== 'string' || !ALLOWED_CATEGORIES.includes(category as ContributionCategory)) {
    throw new Error(`category must be one of: ${ALLOWED_CATEGORIES.join(', ')}`);
  }

  const title = record.title;
  if (typeof title !== 'string') {
    throw new Error('title must be a string.');
  }
  const trimmedTitle = title.trim();
  if (trimmedTitle.length === 0 || trimmedTitle.length > MAX_TITLE_LENGTH) {
    throw new Error(`title must be 1-${MAX_TITLE_LENGTH} characters.`);
  }

  const position = record.position;
  if (typeof position !== 'object' || position === null) {
    throw new Error('position must be an object with x/y.');
  }
  const { x, y } = position as Record<string, unknown>;
  if (typeof x !== 'number' || typeof y !== 'number' || x < 0 || x > 1 || y < 0 || y > 1) {
    throw new Error('position.x and position.y must be numbers in [0, 1].');
  }

  const languageCode = record.languageCode;
  if (typeof languageCode !== 'string' || !ALLOWED_LANGUAGES.includes(languageCode as ContributionLanguage)) {
    throw new Error(`languageCode must be one of: ${ALLOWED_LANGUAGES.join(', ')}`);
  }

  return {
    category: category as ContributionCategory,
    title: trimmedTitle,
    position: { x, y },
    languageCode: languageCode as ContributionLanguage,
  };
}
```

- [ ] **Step 2: Write `contribution.test.ts`**

```typescript
// functions/src/contribution.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateSubmission } from './contribution.js';

const valid = { category: 'landmark', title: 'Great view here', position: { x: 0.5, y: 0.5 }, languageCode: 'en' };

test('validateSubmission accepts a well-formed submission', () => {
  const result = validateSubmission(valid);
  assert.equal(result.category, 'landmark');
  assert.equal(result.title, 'Great view here');
});

test('validateSubmission trims whitespace from title', () => {
  const result = validateSubmission({ ...valid, title: '  padded  ' });
  assert.equal(result.title, 'padded');
});

test('validateSubmission rejects an unknown category', () => {
  assert.throws(() => validateSubmission({ ...valid, category: 'rockstar-hq' }), /category/);
});

test('validateSubmission rejects an empty title', () => {
  assert.throws(() => validateSubmission({ ...valid, title: '   ' }), /title/);
});

test('validateSubmission rejects a title over 280 characters', () => {
  assert.throws(() => validateSubmission({ ...valid, title: 'x'.repeat(281) }), /title/);
});

test('validateSubmission rejects an out-of-range position', () => {
  assert.throws(() => validateSubmission({ ...valid, position: { x: 1.5, y: 0.5 } }), /position/);
});

test('validateSubmission rejects an unsupported language code', () => {
  assert.throws(() => validateSubmission({ ...valid, languageCode: 'ja' }), /languageCode/);
});
```

- [ ] **Step 3: Run the new tests (build first, this project compiles TS before running)**

Run: `cd functions && npm test`
Expected: all `contribution.test.ts` cases PASS (submitContribution.ts doesn't exist yet, so nothing else runs it).

- [ ] **Step 4: Write `submitContribution.ts`**

```typescript
// functions/src/submitContribution.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { validateSubmission } from './contribution.js';

export const submitContribution = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;

  let input;
  try {
    input = validateSubmission(request.data);
  } catch (error) {
    throw new HttpsError('invalid-argument', error instanceof Error ? error.message : 'Invalid submission.');
  }

  const db = getFirestore();
  const profileSnapshot = await db.doc(`profiles/${uid}`).get();
  const authorHandle = profileSnapshot.data()?.handle;
  if (typeof authorHandle !== 'string') {
    // Should never happen: createUserProfile (Plan 5) writes the handle
    // synchronously... except it's an Auth onCreate trigger, so there's a
    // narrow window right after sign-up where the profile doc doesn't
    // exist yet. Surface a retryable error rather than writing a
    // contribution with no author handle.
    throw new HttpsError('failed-precondition', 'Profile not ready yet — try again shortly.');
  }

  const docRef = await db.collection('contributions').add({
    authorUid: uid,
    authorHandle,
    category: input.category,
    title: input.title,
    languageCode: input.languageCode,
    position: input.position,
    status: 'pending',
    upvotes: 0,
    downvotes: 0,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { id: docRef.id };
});
```

- [ ] **Step 5: Add to `index.ts`**

```typescript
export { submitContribution } from './submitContribution.js';
```

- [ ] **Step 6: Run tests and confirm they pass**

Run: `cd functions && npm test`
Expected: `** all tests pass **` (contribution.test.ts + existing handle.test.ts).

- [ ] **Step 7: Commit**

```bash
git add functions/src/contribution.ts functions/src/contribution.test.ts functions/src/submitContribution.ts functions/src/index.ts
git commit -m "feat: submitContribution callable (europe-west1)"
```

---

### Task 2: Cloud Functions `castVote` + `reportContribution`

**Files:**
- Create: `functions/src/vote.ts`
- Create: `functions/src/vote.test.ts`
- Create: `functions/src/castVote.ts`
- Create: `functions/src/reportContribution.ts`
- Modify: `functions/src/index.ts`

**Interfaces:**
- Consumes: `contributions/{id}` document shape from Task 1 (`upvotes`, `downvotes` fields).
- Produces: `applyVoteDelta(previous: 'up' | 'down' | null, next: 'up' | 'down') -> { upvoteDelta: number; downvoteDelta: number }`, exported for the transaction in `castVote.ts`.

- [ ] **Step 1: Write `vote.ts` (pure delta computation, unit-testable)**

```typescript
// functions/src/vote.ts
export type VoteDirection = 'up' | 'down';

export interface VoteDelta {
  upvoteDelta: number;
  downvoteDelta: number;
}

// Re-voting the same direction overwrites the same vote document with no
// count change (spec: "revoter réécrit le même document"). Switching
// direction moves one vote from one bucket to the other.
export function applyVoteDelta(previous: VoteDirection | null, next: VoteDirection): VoteDelta {
  if (previous === next) {
    return { upvoteDelta: 0, downvoteDelta: 0 };
  }
  if (previous === null) {
    return next === 'up' ? { upvoteDelta: 1, downvoteDelta: 0 } : { upvoteDelta: 0, downvoteDelta: 1 };
  }
  // previous is the other direction than next
  return next === 'up' ? { upvoteDelta: 1, downvoteDelta: -1 } : { upvoteDelta: -1, downvoteDelta: 1 };
}
```

- [ ] **Step 2: Write `vote.test.ts`**

```typescript
// functions/src/vote.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyVoteDelta } from './vote.js';

test('first upvote', () => {
  assert.deepEqual(applyVoteDelta(null, 'up'), { upvoteDelta: 1, downvoteDelta: 0 });
});

test('first downvote', () => {
  assert.deepEqual(applyVoteDelta(null, 'down'), { upvoteDelta: 0, downvoteDelta: 1 });
});

test('re-voting the same direction is a no-op', () => {
  assert.deepEqual(applyVoteDelta('up', 'up'), { upvoteDelta: 0, downvoteDelta: 0 });
  assert.deepEqual(applyVoteDelta('down', 'down'), { upvoteDelta: 0, downvoteDelta: 0 });
});

test('switching from up to down moves one vote across buckets', () => {
  assert.deepEqual(applyVoteDelta('up', 'down'), { upvoteDelta: -1, downvoteDelta: 1 });
});

test('switching from down to up moves one vote across buckets', () => {
  assert.deepEqual(applyVoteDelta('down', 'up'), { upvoteDelta: 1, downvoteDelta: -1 });
});
```

- [ ] **Step 3: Run tests, confirm they pass**

Run: `cd functions && npm test`
Expected: all PASS.

- [ ] **Step 4: Write `castVote.ts`**

```typescript
// functions/src/castVote.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { applyVoteDelta, VoteDirection } from './vote.js';

export const castVote = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;

  const spotId = request.data?.spotId;
  const direction = request.data?.direction;
  if (typeof spotId !== 'string' || spotId.length === 0) {
    throw new HttpsError('invalid-argument', 'spotId must be a non-empty string.');
  }
  if (direction !== 'up' && direction !== 'down') {
    throw new HttpsError('invalid-argument', "direction must be 'up' or 'down'.");
  }

  const db = getFirestore();
  const contributionRef = db.doc(`contributions/${spotId}`);
  const voteRef = db.doc(`votes/${spotId}_${uid}`);

  const result = await db.runTransaction(async (transaction) => {
    const [contributionSnapshot, voteSnapshot] = await Promise.all([
      transaction.get(contributionRef),
      transaction.get(voteRef),
    ]);
    if (!contributionSnapshot.exists) {
      throw new HttpsError('not-found', 'Contribution not found.');
    }

    const previousDirection = (voteSnapshot.data()?.direction as VoteDirection | undefined) ?? null;
    const delta = applyVoteDelta(previousDirection, direction as VoteDirection);

    const currentUpvotes = (contributionSnapshot.data()?.upvotes as number | undefined) ?? 0;
    const currentDownvotes = (contributionSnapshot.data()?.downvotes as number | undefined) ?? 0;
    const upvotes = currentUpvotes + delta.upvoteDelta;
    const downvotes = currentDownvotes + delta.downvoteDelta;

    transaction.set(voteRef, { spotId, uid, direction, updatedAt: FieldValue.serverTimestamp() });
    transaction.update(contributionRef, { upvotes, downvotes });

    return { upvotes, downvotes };
  });

  return result;
});
```

- [ ] **Step 5: Write `reportContribution.ts`**

```typescript
// functions/src/reportContribution.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const MAX_REASON_LENGTH = 280;

// Apple 1.2 (UGC) requires the reporting mechanism to exist even before
// there's an active moderation queue reading `reports` — triage of this
// collection is Plan 5c's job, not this task's.
export const reportContribution = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  const spotId = request.data?.spotId;
  if (typeof spotId !== 'string' || spotId.length === 0) {
    throw new HttpsError('invalid-argument', 'spotId must be a non-empty string.');
  }
  const reason = request.data?.reason;
  if (reason !== undefined && (typeof reason !== 'string' || reason.length > MAX_REASON_LENGTH)) {
    throw new HttpsError('invalid-argument', `reason must be a string of at most ${MAX_REASON_LENGTH} characters.`);
  }

  const db = getFirestore();
  const contributionSnapshot = await db.doc(`contributions/${spotId}`).get();
  if (!contributionSnapshot.exists) {
    throw new HttpsError('not-found', 'Contribution not found.');
  }

  await db.collection('reports').add({
    contributionId: spotId,
    reporterUid: request.auth.uid,
    reason: reason ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { reported: true };
});
```

- [ ] **Step 6: Add to `index.ts`**

```typescript
export { castVote } from './castVote.js';
export { reportContribution } from './reportContribution.js';
```

- [ ] **Step 7: Run tests, confirm they pass**

Run: `cd functions && npm test`
Expected: `** all tests pass **`.

- [ ] **Step 8: Commit**

```bash
git add functions/src/vote.ts functions/src/vote.test.ts functions/src/castVote.ts functions/src/reportContribution.ts functions/src/index.ts
git commit -m "feat: castVote + reportContribution callables (europe-west1)"
```

---

### Task 3: `deleteAccount` cascade + Firestore Security Rules

**Files:**
- Modify: `functions/src/deleteAccount.ts`
- Modify: `firestore.rules`

**Interfaces:**
- Consumes: `contributions` (Task 1), `votes` (Task 2) collection shapes.

- [ ] **Step 1: Update `deleteAccount.ts` to cascade into contributions and votes**

```typescript
// functions/src/deleteAccount.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const ANONYMIZED_HANDLE = 'DELETED-AUTHOR';

// Plan 5b cascade (was a known gap flagged in Plan 5's self-review):
// - approved contributions are ANONYMIZED, never deleted (spec: the
//   community map data is preserved, only the identifying author fields
//   are stripped — this is what takes the record out of GDPR scope
//   without losing the map content).
// - pending/rejected contributions were never shown publicly, so they're
//   deleted outright rather than anonymized (nothing worth preserving).
// - all vote documents by this uid are deleted (spec: "profil et votes
//   effacés"). Aggregate upvote/downvote counts on other users' spots are
//   intentionally left as-is — they reflect real community sentiment and
//   the spec doesn't ask for them to be unwound.
export const deleteAccount = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;
  const db = getFirestore();

  const [ownedContributions, ownedVotes] = await Promise.all([
    db.collection('contributions').where('authorUid', '==', uid).get(),
    db.collection('votes').where('uid', '==', uid).get(),
  ]);

  const batch = db.batch();
  for (const doc of ownedContributions.docs) {
    if (doc.data().status === 'approved') {
      batch.update(doc.ref, { authorUid: null, authorHandle: ANONYMIZED_HANDLE });
    } else {
      batch.delete(doc.ref);
    }
  }
  for (const doc of ownedVotes.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();

  await db.doc(`profiles/${uid}`).delete();
  await getAuth().deleteUser(uid);
  return { deleted: true };
});
```

- [ ] **Step 2: Update `firestore.rules`**

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
    match /contributions/{id} {
      allow read: if resource.data.status == 'approved'
        || (request.auth != null && request.auth.uid == resource.data.authorUid);
      allow write: if false;
    }
    match /votes/{id} {
      allow read: if request.auth != null && request.auth.uid == resource.data.uid;
      allow write: if false;
    }
    match /reports/{id} {
      allow read, write: if false;
    }
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

- [ ] **Step 3: Start the Firestore emulator to confirm the rules file compiles**

Run: `firebase emulators:start --only firestore` (Ctrl+C once it logs it's running)
Expected: no rules-compilation error in the log.

- [ ] **Step 4: Run the Cloud Functions test suite (deleteAccount has no dedicated unit test — this confirms the build still compiles)**

Run: `cd functions && npm test`
Expected: `** all tests pass **`, build succeeds (this is a TypeScript compile check as much as a test run).

- [ ] **Step 5: Commit**

```bash
git add functions/src/deleteAccount.ts firestore.rules
git commit -m "feat: cascade deleteAccount into contributions/votes, add contributions/votes/reports security rules"
```

---

### Task 4: Swift `Core/Community/` layer

**Files:**
- Create: `NeonCompass/Core/Community/Contribution.swift`
- Create: `NeonCompass/Core/Community/BlockedContributor.swift`
- Create: `NeonCompass/Core/Community/ContributionRepository.swift`
- Create: `NeonCompass/Core/Community/FirestoreContributionRepository.swift`
- Create: `NeonCompass/Core/Community/ContributionFunctionsCalling.swift`
- Create: `NeonCompass/Core/Community/FirebaseContributionFunctions.swift`
- Modify: `NeonCompass/App/NeonCompassApp.swift`

**Interfaces:**
- Consumes: `POICategory` (`NeonCompass/Features/Map/POI.swift` — actually defined alongside `POI`), `NormalizedPoint` (same file).
- Produces: `Contribution`, `Contribution.Status`, `VoteDirection`, `ContributionRepository.fetchApproved()/fetchMine(uid:)`, `ContributionFunctionsCalling.submitContribution/castVote/reportContribution`, `BlockedContributor` SwiftData model — all consumed by Task 5's `CommunityModel`.

- [ ] **Step 1: Write `Contribution.swift` — no Firebase import, plain domain model**

```swift
import Foundation

/// Miroir (partiel) du document `contributions/{id}` — jamais écrit
/// directement par le client (Security Rules : write toujours refusé sur
/// cette collection, tout passe par les Cloud Functions submitContribution/
/// castVote/reportContribution). `createdAt` n'est volontairement pas
/// modélisé ici : ce plan n'affiche pas de date, et FirestoreContributionRepository
/// décode via document.data(as:), qui ignore silencieusement les champs non
/// déclarés — voir ce fichier pour pourquoi JSONSerialization est interdit
/// (Timestamp non sérialisable).
struct Contribution: Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending, approved, rejected
    }

    let id: String
    let authorUid: String?
    let authorHandle: String
    let category: POICategory
    let title: String
    let languageCode: String
    let position: NormalizedPoint
    let status: Status
    let upvotes: Int
    let downvotes: Int
}
```

- [ ] **Step 2: Write `BlockedContributor.swift`**

```swift
import Foundation
import SwiftData

/// Blocage strictement local (Apple 1.2 — "masquer tous les spots d'un
/// contributeur" est une liste locale, réversible, gérable dans les
/// réglages — jamais envoyée au serveur).
@Model
final class BlockedContributor {
    @Attribute(.unique) var authorUid: String
    var blockedAt: Date

    init(authorUid: String, blockedAt: Date = .now) {
        self.authorUid = authorUid
        self.blockedAt = blockedAt
    }
}
```

- [ ] **Step 3: Write `ContributionRepository.swift`**

```swift
import Foundation

protocol ContributionRepository: Sendable {
    func fetchApproved() async throws -> [Contribution]
    func fetchMine(uid: String) async throws -> [Contribution]
}
```

- [ ] **Step 4: Write `FirestoreContributionRepository.swift`**

```swift
import FirebaseFirestore

/// Décode toujours via document.data(as:) (Codable natif Firestore),
/// jamais JSONSerialization.data(withJSONObject:) — contributions a un
/// champ createdAt: Timestamp, non sérialisable par JSONSerialization, qui
/// lève une exception Objective-C non rattrapable (bug corrigé au Plan 5
/// sur FirestoreProfileRepository).
final class FirestoreContributionRepository: ContributionRepository {
    /// Miroir du document Firestore, sans l'id (qui vient de document.documentID,
    /// pas du corps du document).
    private struct Body: Decodable {
        let authorUid: String?
        let authorHandle: String
        let category: POICategory
        let title: String
        let languageCode: String
        let position: NormalizedPoint
        let status: Contribution.Status
        let upvotes: Int
        let downvotes: Int
    }

    nonisolated(unsafe) private let collection: CollectionReference
    private let typeName = "Contribution"

    init(firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection("contributions")
    }

    func fetchApproved() async throws -> [Contribution] {
        let snapshot = try await collection
            .whereField("status", isEqualTo: Contribution.Status.approved.rawValue)
            .getDocuments()
        return decode(snapshot.documents)
    }

    func fetchMine(uid: String) async throws -> [Contribution] {
        let snapshot = try await collection
            .whereField("authorUid", isEqualTo: uid)
            .getDocuments()
        return decode(snapshot.documents)
    }

    private func decode(_ documents: [QueryDocumentSnapshot]) -> [Contribution] {
        documents.compactMap { document in
            do {
                let body = try document.data(as: Body.self)
                return Contribution(
                    id: document.documentID,
                    authorUid: body.authorUid,
                    authorHandle: body.authorHandle,
                    category: body.category,
                    title: body.title,
                    languageCode: body.languageCode,
                    position: body.position,
                    status: body.status,
                    upvotes: body.upvotes,
                    downvotes: body.downvotes
                )
            } catch {
                // A single malformed document must not blank the whole
                // result — same tolerance policy as FirestoreContentRepository.
                print("FirestoreContributionRepository: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
```

- [ ] **Step 5: Write `ContributionFunctionsCalling.swift`**

```swift
import Foundation

enum VoteDirection: String, Sendable {
    case up, down
}

protocol ContributionFunctionsCalling: Sendable {
    func submitContribution(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws
    func castVote(spotId: String, direction: VoteDirection) async throws
    func reportContribution(spotId: String, reason: String?) async throws
}
```

- [ ] **Step 6: Write `FirebaseContributionFunctions.swift`**

```swift
import Foundation
@preconcurrency import FirebaseFunctions

/// Implémentation réelle de ContributionFunctionsCalling, région
/// europe-west1 (miroir de functions/src/submitContribution.ts,
/// castVote.ts, reportContribution.ts).
final class FirebaseContributionFunctions: ContributionFunctionsCalling {
    nonisolated(unsafe) private let functions: Functions

    init(functions: Functions = Functions.functions(region: "europe-west1")) {
        self.functions = functions
    }

    func submitContribution(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        _ = try await functions.httpsCallable("submitContribution").call([
            "category": category.rawValue,
            "title": title,
            "position": ["x": position.x, "y": position.y],
            "languageCode": languageCode,
        ])
    }

    func castVote(spotId: String, direction: VoteDirection) async throws {
        _ = try await functions.httpsCallable("castVote").call([
            "spotId": spotId,
            "direction": direction.rawValue,
        ])
    }

    func reportContribution(spotId: String, reason: String?) async throws {
        var payload: [String: Any] = ["spotId": spotId]
        if let reason {
            payload["reason"] = reason
        }
        _ = try await functions.httpsCallable("reportContribution").call(payload)
    }
}
```

- [ ] **Step 7: Add `BlockedContributor` to the model container**

In `NeonCompass/App/NeonCompassApp.swift`, change:

```swift
.modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self, TrophyProgress.self])
```

to:

```swift
.modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self, TrophyProgress.self, BlockedContributor.self])
```

- [ ] **Step 8: Build to confirm the new files compile**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add NeonCompass/Core/Community NeonCompass/App/NeonCompassApp.swift
git commit -m "feat: Core/Community protocols + Firebase-backed implementations"
```

---

### Task 5: `CommunityModel` + fakes + unit tests

**Files:**
- Create: `NeonCompass/Features/Community/CommunityModel.swift`
- Create: `NeonCompassTests/Community/CommunityFakesTests.swift`

**Interfaces:**
- Consumes: `ContributionRepository`, `ContributionFunctionsCalling`, `Contribution`, `VoteDirection`, `BlockedContributor` (Task 4).
- Produces: `CommunityModel` — consumed by Task 6's `MapScreen`/`ContributionSubmissionSheet`/`ContributionAnnotationView` and Task 7's `ProfileScreen`. Exact surface:
  - `var visibleSpots: [Contribution]` (approved spots minus blocked authors)
  - `var myContributions: [Contribution]`
  - `func loadApprovedSpots() async`
  - `func loadMyContributions(uid: String) async`
  - `func submit(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws`
  - `func vote(on spot: Contribution, direction: VoteDirection) async`
  - `func report(_ spot: Contribution, reason: String?) async`
  - `func isBlocked(authorUid: String) -> Bool`
  - `func block(authorUid: String)`
  - `func unblock(authorUid: String)`
  - `var blockedAuthorUIDs: Set<String>` (for the settings list)

- [ ] **Step 1: Write `CommunityModel.swift`**

```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CommunityModel {
    private(set) var approvedSpots: [Contribution] = []
    private(set) var myContributions: [Contribution] = []
    private(set) var blockedAuthorUIDs: Set<String>

    private let repository: ContributionRepository
    private let functions: ContributionFunctionsCalling
    private let modelContext: ModelContext

    init(repository: ContributionRepository, functions: ContributionFunctionsCalling, modelContext: ModelContext) {
        self.repository = repository
        self.functions = functions
        self.modelContext = modelContext
        self.blockedAuthorUIDs = Set((try? modelContext.fetch(FetchDescriptor<BlockedContributor>()))?.map(\.authorUid) ?? [])
    }

    var visibleSpots: [Contribution] {
        approvedSpots.filter { spot in
            guard let authorUid = spot.authorUid else { return true }
            return !blockedAuthorUIDs.contains(authorUid)
        }
    }

    func loadApprovedSpots() async {
        approvedSpots = (try? await repository.fetchApproved()) ?? []
    }

    func loadMyContributions(uid: String) async {
        myContributions = (try? await repository.fetchMine(uid: uid)) ?? []
    }

    func submit(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        try await functions.submitContribution(category: category, title: title, position: position, languageCode: languageCode)
    }

    func vote(on spot: Contribution, direction: VoteDirection) async {
        try? await functions.castVote(spotId: spot.id, direction: direction)
    }

    func report(_ spot: Contribution, reason: String?) async {
        try? await functions.reportContribution(spotId: spot.id, reason: reason)
    }

    func isBlocked(authorUid: String) -> Bool {
        blockedAuthorUIDs.contains(authorUid)
    }

    func block(authorUid: String) {
        guard !blockedAuthorUIDs.contains(authorUid) else { return }
        modelContext.insert(BlockedContributor(authorUid: authorUid))
        blockedAuthorUIDs.insert(authorUid)
        try? modelContext.save()
    }

    func unblock(authorUid: String) {
        let descriptor = FetchDescriptor<BlockedContributor>(predicate: #Predicate { $0.authorUid == authorUid })
        guard let existing = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(existing)
        blockedAuthorUIDs.remove(authorUid)
        try? modelContext.save()
    }
}
```

- [ ] **Step 2: Write fakes + tests**

```swift
import Testing
@testable import NeonCompass

final class FakeContributionRepository: ContributionRepository {
    nonisolated(unsafe) var approvedToReturn: [Contribution] = []
    nonisolated(unsafe) var mineToReturn: [Contribution] = []

    func fetchApproved() async throws -> [Contribution] { approvedToReturn }
    func fetchMine(uid: String) async throws -> [Contribution] { mineToReturn }
}

final class FakeContributionFunctions: ContributionFunctionsCalling {
    nonisolated(unsafe) private(set) var submitCallCount = 0
    nonisolated(unsafe) private(set) var lastVote: (spotId: String, direction: VoteDirection)?
    nonisolated(unsafe) private(set) var lastReport: (spotId: String, reason: String?)?

    func submitContribution(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        submitCallCount += 1
    }

    func castVote(spotId: String, direction: VoteDirection) async throws {
        lastVote = (spotId, direction)
    }

    func reportContribution(spotId: String, reason: String?) async throws {
        lastReport = (spotId, reason)
    }
}

private func makeSpot(id: String, authorUid: String?) -> Contribution {
    Contribution(
        id: id,
        authorUid: authorUid,
        authorHandle: "NEON-FALCON-88",
        category: .landmark,
        title: "A great spot",
        languageCode: "en",
        position: NormalizedPoint(x: 0.5, y: 0.5),
        status: .approved,
        upvotes: 0,
        downvotes: 0
    )
}

@MainActor
struct CommunityFakesTests {
    @Test func visibleSpotsExcludesBlockedAuthors() async throws {
        let repository = FakeContributionRepository()
        repository.approvedToReturn = [makeSpot(id: "1", authorUid: "author-a"), makeSpot(id: "2", authorUid: "author-b")]
        let container = try ModelContainer(for: BlockedContributor.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CommunityModel(repository: repository, functions: FakeContributionFunctions(), modelContext: ModelContext(container))

        await model.loadApprovedSpots()
        model.block(authorUid: "author-a")

        #expect(model.visibleSpots.map(\.id) == ["2"])
    }

    @Test func voteCallsCastVoteWithSpotIDAndDirection() async throws {
        let functions = FakeContributionFunctions()
        let container = try ModelContainer(for: BlockedContributor.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CommunityModel(repository: FakeContributionRepository(), functions: functions, modelContext: ModelContext(container))
        let spot = makeSpot(id: "spot-1", authorUid: "author-a")

        await model.vote(on: spot, direction: .up)

        #expect(functions.lastVote?.spotId == "spot-1")
        #expect(functions.lastVote?.direction == .up)
    }

    @Test func blockThenUnblockRestoresVisibility() throws {
        let container = try ModelContainer(for: BlockedContributor.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CommunityModel(repository: FakeContributionRepository(), functions: FakeContributionFunctions(), modelContext: ModelContext(container))

        model.block(authorUid: "author-a")
        #expect(model.isBlocked(authorUid: "author-a"))

        model.unblock(authorUid: "author-a")
        #expect(!model.isBlocked(authorUid: "author-a"))
    }
}
```

- [ ] **Step 3: Run tests**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, all new `CommunityFakesTests` pass alongside the existing suite.

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Community/CommunityModel.swift NeonCompassTests/Community/CommunityFakesTests.swift
git commit -m "feat: CommunityModel (approved spots, my contributions, vote, report, local block list)"
```

---

### Task 6: Map UI — menu appui-long, soumission, affichage des spots

**Files:**
- Create: `NeonCompass/Features/Community/ContributionSubmissionSheet.swift`
- Create: `NeonCompass/Features/Community/ContributionAnnotationView.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CommunityModel` (Task 5), `AuthModel`/`FirebaseAuthProvider` (Plan 5, for `currentUserID` — a signed-out user long-pressing "Proposer un spot" must be routed to sign-in, not crash on a nil uid).

- [ ] **Step 1: Add new `Localizable.xcstrings` entries**

Open `NeonCompass/Resources/Localizable.xcstrings`. Each entry follows the exact existing pattern (see `cheats.search.placeholder` for a template: one `"<key>"` object with `"localizations": { "en": { "stringUnit": { "state": "translated", "value": "<EN text>" } } }`). Insert these into the `"strings"` object (alphabetical position, matching existing ordering), one entry per row below:

| Key | EN value |
|---|---|
| `map.longPress.menuTitle` | What do you want to do here? |
| `map.longPress.addPersonalPin` | Add a personal pin |
| `map.longPress.proposeSpot` | Propose a spot |
| `map.longPress.cancel` | Cancel |
| `map.contribution.signInRequired` | Sign in to propose a spot. |
| `map.contribution.sheetTitle` | Propose a spot |
| `map.contribution.categoryLabel` | Category |
| `map.contribution.titlePlaceholder` | What's here? (280 characters max) |
| `map.contribution.submit` | Submit |
| `map.contribution.cancel` | Cancel |
| `map.contribution.submitted` | Submitted for review — thanks! |
| `map.contribution.error` | Something went wrong — try again. |
| `map.spot.communityBadge` | Community |
| `map.spot.report` | Report |
| `map.spot.reportSent` | Reported — thanks for flagging it. |
| `map.spot.blockAuthor` | Hide this contributor's spots |
| `map.spot.blockConfirmTitle` | Hide %@'s spots? |
| `map.spot.blockConfirmMessage` | You won't see their spots anymore. You can undo this in Settings. |
| `map.spot.blockConfirm` | Hide |
| `map.spot.blockCancel` | Cancel |

- [ ] **Step 2: Write `ContributionSubmissionSheet.swift`**

```swift
import SwiftUI

struct ContributionSubmissionSheet: View {
    let position: NormalizedPoint
    let onSubmit: (POICategory, String) async -> Void
    let onDismiss: () -> Void

    @State private var category: POICategory = .landmark
    @State private var title: String = ""
    @State private var isSubmitting = false

    private var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 280
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("map.contribution.categoryLabel", selection: $category) {
                    ForEach(POICategory.allCases, id: \.self) { category in
                        Text(category.localizedNameKey).tag(category)
                    }
                }
                TextField("map.contribution.titlePlaceholder", text: $title, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle(Text("map.contribution.sheetTitle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("map.contribution.cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("map.contribution.submit") {
                        isSubmitting = true
                        Task {
                            await onSubmit(category, title.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSubmitting = false
                        }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Write `ContributionAnnotationView.swift` (pin + vote/report/block popover)**

```swift
import SwiftUI

struct ContributionAnnotationView: View {
    let spot: Contribution
    let onVote: (VoteDirection) -> Void
    let onReport: () -> Void
    let onBlockAuthor: () -> Void

    @State private var showDetail = false
    @State private var showBlockConfirmation = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(NCColor.neonCyan)
        }
        .popover(isPresented: $showDetail) {
            detail
                .padding(16)
                .frame(minWidth: 260)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(spot.title)
                    .font(NCTypography.body)
                Spacer()
                Text("map.spot.communityBadge")
                    .font(.caption)
                    .foregroundStyle(NCColor.sunsetMagenta)
            }
            Text(spot.authorHandle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    onVote(.up)
                } label: {
                    Label("\(spot.upvotes)", systemImage: "arrow.up")
                }
                Button {
                    onVote(.down)
                } label: {
                    Label("\(spot.downvotes)", systemImage: "arrow.down")
                }
                Spacer()
                Button("map.spot.report", action: onReport)
                if let authorUid = spot.authorUid {
                    Button("map.spot.blockAuthor") {
                        showBlockConfirmation = true
                    }
                    .confirmationDialog(
                        Text("map.spot.blockConfirmTitle \(spot.authorHandle)"),
                        isPresented: $showBlockConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("map.spot.blockConfirm", role: .destructive) {
                            onBlockAuthor()
                            showDetail = false
                        }
                        Button("map.spot.blockCancel", role: .cancel) {}
                    } message: {
                        Text("map.spot.blockConfirmMessage")
                    }
                    .id(authorUid) // scope the confirmationDialog state to this spot's author
                }
            }
        }
    }
}
```

Note: `Text("map.spot.blockConfirmTitle \(spot.authorHandle)")` relies on the String Catalog's `%@` substitution — SwiftUI's `Text(_:)` string-interpolation initializer resolves `%@`-style catalog entries this way natively (same pattern already used nowhere else in this codebase yet, but it's the standard SwiftUI String Catalog mechanism — no custom formatting code needed).

- [ ] **Step 4: Wire into `MapScreen.swift`**

Replace the existing long-press handling. Current code (from Plan 2):

```swift
    @State private var pendingPinLocation: NormalizedPoint?
    @State private var pendingPinTitle = ""
```

becomes:

```swift
    @State private var pendingPinLocation: NormalizedPoint?
    @State private var pendingPinTitle = ""
    @State private var showLongPressMenu = false
    @State private var pendingContributionLocation: NormalizedPoint?
    @State private var communityModel: CommunityModel?
    @State private var authModel = AuthModel(authProvider: FirebaseAuthProvider())
```

The `TiledMapRepresentable` closure changes from directly setting `pendingPinLocation` to opening the choice menu:

```swift
            TiledMapRepresentable(manifest: manifest, viewport: $viewport) { canvasPoint in
                pendingPinLocation = MapGeometry.normalizedPoint(fromCanvasPoint: canvasPoint, manifest: manifest)
                showLongPressMenu = true
            }
```

Add the choice menu and the community overlay/sheet alongside the existing `PersonalPinsOverlay` and alert, inside `mapCanvas(model:)`:

```swift
            if let communityModel {
                ForEach(communityModel.visibleSpots) { spot in
                    let point = spot.position
                    let position = MapGeometry.screenPosition(for: point, manifest: manifest, viewport: viewport)
                    ContributionAnnotationView(
                        spot: spot,
                        onVote: { direction in Task { await communityModel.vote(on: spot, direction: direction) } },
                        onReport: { Task { await communityModel.report(spot, reason: nil) } },
                        onBlockAuthor: {
                            if let authorUid = spot.authorUid { communityModel.block(authorUid: authorUid) }
                        }
                    )
                    .position(position)
                }
            }
```

Replace the existing `.alert("map.personalPins.addPrompt", ...)` block's presentation condition — it currently fires whenever `pendingPinLocation != nil`. Gate it behind the menu choice instead: add a `.confirmationDialog` bound to `showLongPressMenu` that either arms the existing alert flow (already keyed off `pendingPinLocation`) or opens the contribution sheet:

```swift
        .confirmationDialog("map.longPress.menuTitle", isPresented: $showLongPressMenu, titleVisibility: .visible) {
            Button("map.longPress.addPersonalPin") {
                // pendingPinLocation is already set — the existing
                // .alert(isPresented: pendingPinLocation != nil) below fires next.
            }
            Button("map.longPress.proposeSpot") {
                if authModel.userID != nil {
                    pendingContributionLocation = pendingPinLocation
                }
                pendingPinLocation = nil
            }
            Button("map.longPress.cancel", role: .cancel) {
                pendingPinLocation = nil
            }
        }
        .sheet(item: Binding(
            get: { pendingContributionLocation.map { ContributionLocationBox(location: $0) } },
            set: { pendingContributionLocation = $0?.location }
        )) { box in
            if let communityModel {
                ContributionSubmissionSheet(
                    position: box.location,
                    onSubmit: { category, title in
                        try? await communityModel.submit(category: category, title: title, position: box.location, languageCode: Self.currentLanguageCode())
                        pendingContributionLocation = nil
                    },
                    onDismiss: { pendingContributionLocation = nil }
                )
                .presentationDetents([.medium])
            }
        }
```

Add the small `Identifiable` wrapper (sheets need an `Identifiable` item, `NormalizedPoint` isn't one) and the language helper, near the bottom of the file:

```swift
private struct ContributionLocationBox: Identifiable {
    let location: NormalizedPoint
    var id: String { "\(location.x)-\(location.y)" }
}

extension MapScreen {
    static func currentLanguageCode() -> String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let supported = ["en", "fr", "es", "it", "de"]
        return supported.contains(code) ? code : "en"
    }
}
```

In `loadModel()`, initialize `communityModel` alongside the existing POI content store (guard the same `FirebaseAvailability.isConfigured` check used for POIs):

```swift
    private func loadModel() {
        guard model == nil else { return }
        guard FirebaseAvailability.isConfigured else {
            model = MapModel(pois: [], modelContext: modelContext)
            return
        }
        let contentStore = ContentStore<POI>(
            collectionName: "poi",
            remote: FirestoreContentRepository<POI>(collectionName: "poi"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = MapModel(pois: contentStore.items, modelContext: modelContext)
        communityModel = CommunityModel(
            repository: FirestoreContributionRepository(),
            functions: FirebaseContributionFunctions(),
            modelContext: modelContext
        )
        Task {
            try? await contentStore.syncIfNeeded()
            model?.updatePOIs(contentStore.items)
            await communityModel?.loadApprovedSpots()
        }
    }
```

- [ ] **Step 5: Build to confirm it compiles**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run tests**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, existing Map-related tests unaffected (this task added no new Swift unit tests — the long-press menu and sheet wiring are UI glue covered by the manual smoke test in Step 7, matching how `PersonalPinListSheet`/`MapFilterControls` were introduced in Plan 2 without dedicated view tests).

- [ ] **Step 7: Manual smoke test in the simulator**

Run: `Scripts/build.sh` then launch the app in the iOS Simulator (Xcode or `xcrun simctl`). Long-press the map: confirm the choice menu appears with both options. Choose "Add a personal pin": confirm the existing alert flow still works unchanged. Long-press again, choose "Propose a spot" while signed out: confirm nothing crashes and no sheet appears (silently no-ops per the `authModel.userID != nil` guard — Step 4 above does not yet show a sign-in prompt inline; this is a known UX gap, not a bug, see Task 7's note). Sign in via the Profile tab, long-press, choose "Propose a spot": confirm the sheet opens, fill a title, submit, confirm no crash. (Approving a spot to visually confirm it renders on the map requires manually flipping its Firestore `status` field to `approved` in the console/emulator — there is no moderation UI yet, that's Plan 5c.)

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Features/Community/ContributionSubmissionSheet.swift NeonCompass/Features/Community/ContributionAnnotationView.swift NeonCompass/Features/Map/MapScreen.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: long-press menu (personal pin / propose a spot), contribution submission sheet, community spot overlay with vote/report/block"
```

---

### Task 7: Profile — "Mes contributions" + contributeurs bloqués

**Files:**
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CommunityModel.myContributions`, `CommunityModel.blockedAuthorUIDs`/`unblock` (Task 5).

- [ ] **Step 1: Add new `Localizable.xcstrings` entries**

Same pattern as Task 6 Step 1:

| Key | EN value |
|---|---|
| `profile.myContributions.title` | My contributions |
| `profile.myContributions.empty` | No contributions yet. |
| `profile.myContributions.status.pending` | Pending review |
| `profile.myContributions.status.approved` | Approved |
| `profile.myContributions.status.rejected` | Rejected |
| `profile.blockedContributors.title` | Hidden contributors |
| `profile.blockedContributors.empty` | You haven't hidden anyone. |
| `profile.blockedContributors.unblock` | Unhide |

- [ ] **Step 2: Wire `CommunityModel` and the two new sections into `ProfileScreen.swift`**

Add the model as `@State`:

```swift
    @State private var communityModel = CommunityModel(
        repository: FirestoreContributionRepository(),
        functions: FirebaseContributionFunctions(),
        modelContext: nil // placeholder — see below
    )
```

`CommunityModel.init` requires a non-optional `ModelContext` (Task 5), which isn't available until the view's `@Environment(\.modelContext)` resolves — mirror the existing `MapScreen`/`FeedScreen` pattern of deferring construction into an optional `@State` set inside `.task`, rather than at property-init time:

```swift
    @Environment(\.modelContext) private var modelContext
    @State private var communityModel: CommunityModel?
```

and in `.task(id: authModel.userID)`, after the existing profile load:

```swift
        .task(id: authModel.userID) {
            if let userID = authModel.userID {
                await profileModel.loadProfile(uid: userID)
                if communityModel == nil {
                    communityModel = CommunityModel(
                        repository: FirestoreContributionRepository(),
                        functions: FirebaseContributionFunctions(),
                        modelContext: modelContext
                    )
                }
                await communityModel?.loadMyContributions(uid: userID)
            }
        }
```

In `signedInContent(userID:)`, after the existing delete-account button, add the two sections:

```swift
    private func signedInContent(userID: String) -> some View {
        VStack(spacing: 16) {
            Text(profileModel.profile?.handle ?? "…")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)

            Button("profile.handle.regenerate") {
                Task { try? await profileModel.regenerateHandle() }
            }

            if let communityModel {
                myContributionsSection(communityModel)
                blockedContributorsSection(communityModel)
            }

            Button("profile.signOut") {
                try? authModel.signOut()
            }

            Button("profile.deleteAccount", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    private func myContributionsSection(_ communityModel: CommunityModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.myContributions.title")
                .font(NCTypography.body)
                .foregroundStyle(.white)
            if communityModel.myContributions.isEmpty {
                Text("profile.myContributions.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(communityModel.myContributions) { contribution in
                    HStack {
                        Text(contribution.title)
                        Spacer()
                        Text(statusKey(contribution.status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func blockedContributorsSection(_ communityModel: CommunityModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.blockedContributors.title")
                .font(NCTypography.body)
                .foregroundStyle(.white)
            if communityModel.blockedAuthorUIDs.isEmpty {
                Text("profile.blockedContributors.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(communityModel.blockedAuthorUIDs), id: \.self) { authorUid in
                    HStack {
                        Text(authorUid)
                        Spacer()
                        Button("profile.blockedContributors.unblock") {
                            communityModel.unblock(authorUid: authorUid)
                        }
                    }
                }
            }
        }
    }

    private func statusKey(_ status: Contribution.Status) -> LocalizedStringKey {
        switch status {
        case .pending: "profile.myContributions.status.pending"
        case .approved: "profile.myContributions.status.approved"
        case .rejected: "profile.myContributions.status.rejected"
        }
    }
```

`import SwiftUI` already present in `ProfileScreen.swift`; `LocalizedStringKey` needs no extra import.

Note: `blockedContributorsSection` displays the raw `authorUid`, not a handle — `BlockedContributor` only stores the UID (Task 4), and there's no repository method to resolve a UID back to a handle for someone whose spots you've hidden (contributions carry `authorHandle` at read time, but a blocked author's spots are filtered out of `visibleSpots` precisely so they're never fetched-and-displayed again — resolving a friendly name here would mean fetching data about someone specifically to unblock them, an edge case not worth solving in this plan). Acceptable for v1; flag as a known rough edge, not a defect.

- [ ] **Step 3: Build to confirm it compiles**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run tests**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Profile/ProfileScreen.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: Profile shows my contributions history and hidden-contributors management"
```

---

## Self-Review

**Spec coverage:**
- "appui long → proposer un spot (catégorie, titre, note ≤ 280 caractères, position)" — Task 6. ✅
- "spots approuvés badgés communauté, votes ▲▼, signalement" — Task 6 (`ContributionAnnotationView`). ✅
- "masquer les spots de ce contributeur" (blocage local, réversible dans les réglages) — Task 4 (`BlockedContributor`), Task 6 (block action), Task 7 (unblock in Profile). ✅
- "jamais d'écriture directe du client... Cloud Functions callable" — Task 1/2 (`submitContribution`/`castVote`), Security Rules Task 3. ✅
- "Votes uniques par construction : ID `{spotId}_{uid}`" — Task 2 `castVote.ts`. ✅
- "Historique de mes contributions avec leurs statuts" — Task 7. ✅
- "Suppression de compte... contributions approuvées anonymisées" — Task 3 `deleteAccount.ts`. ✅
- XP/leveling à l'approbation, App Check, cooldown, dédup géo, filtre vocabulaire, vélocité/shadow-ban, file de modération — explicitly out of scope (Plan 5c), called out in Global Constraints.

**Known gaps carried forward, not silently dropped:**
- Task 6 Step 7 notes a real UX gap: choosing "Propose a spot" while signed out silently does nothing rather than prompting sign-in. Small and self-contained enough to fix as a fast-follow, but flagging it here rather than pretending it's handled.
- Task 7 leaves blocked-contributor rows showing a raw UID instead of a handle — documented as an accepted rough edge, not a defect.
- `reports` collection has no reader yet (moderator tooling is Plan 5c) — by design, not an oversight.
