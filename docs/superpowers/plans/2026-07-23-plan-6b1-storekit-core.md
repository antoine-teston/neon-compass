# Plan 6b-1 — StoreKit 2 core (Pro entitlement, paywall, ad removal) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the foundational "is this user Pro" infrastructure everything else in Plan 6b gates on — StoreKit 2 purchase/restore, a locally-authoritative entitlement model shared app-wide, a paywall screen, ad removal for entitled users, and a best-effort account-badge mirror via App Store Server Notifications V2. First sub-plan of "StoreKit 2 Pro" (roadmap Plan 6b, split into Core / Simple Features / Widgets+Notifications per product decision 2026-07-23).

**Architecture:** A new `Core/Store/` layer (protocol + StoreKit-2-backed implementation, mirroring every other `Core/*` layer's Firebase/SDK-behind-protocols convention). One `@Observable` `ProEntitlementModel` is constructed once at `RootView` and injected via `.environment(...)` — this is a deliberate repeat of the exact fix Plan 6a's review cycle applied to `AuthModel` (per-screen duplicate instances desync), so this plan builds it shared from the start rather than discovering the bug the hard way a third time. The StoreKit entitlement is the **only** source of truth for gating Pro features on-device; the Firestore `profiles/{uid}.isPremium` field is a best-effort server mirror used only for the profile badge, updated by a new Cloud Function reacting to App Store Server Notifications V2 — never read for gating.

**Tech Stack:** StoreKit 2 (`Product`, `Transaction`, `Product.PurchaseOption.appAccountToken`), a new Cloud Function (App Store Server Notifications V2 webhook, Node 22/TS/ESM, `firebase-functions` v6).

## Global Constraints

- **The StoreKit entitlement is the local source of truth, always.** No Pro-gated feature in this app may ever check `profiles/{uid}.isPremium` to decide whether to unlock itself — only `ProEntitlementModel.isProEntitled` (backed by `Transaction.currentEntitlements`/`Transaction.updates`). The Firestore field exists solely for the account badge and is a mirror, never a gate (spec §"Pro": "L'entitlement StoreKit signé par Apple est la source de vérité locale ; le compte n'en est qu'un miroir serveur").
- **Purchase never requires sign-in.** `purchasePro()`/`restorePurchases()` must work identically whether `AuthModel.userID` is `nil` or not. The `appAccountToken` linkage (for the server mirror) is attached opportunistically only when signed in — its absence must never block or degrade the purchase flow itself.
- **Never gate facts, only comfort.** This plan (and Plan 6b-2/6b-3) must never paywall cheats, map data, or guides — only ads, cloud sync, the route planner, the "what's left" toggle, widgets, followed notifications, and cosmetic themes/icons/badge (spec §"Pro": "jamais les faits... jamais d'XP").
- **One `ProEntitlementModel` instance, injected via environment** — the exact same architectural fix Plan 6a applied to `AuthModel` after finding per-screen duplicates desync on iPad's stable `TabView`. Do not reintroduce a per-screen `@State` instance anywhere.
- **Firebase/StoreKit stays behind protocols in `Core/`** — features (`Features/Profile`, `Features/Feed`, etc.) never call `Product`/`Transaction` APIs directly, only `Core/Store/`'s protocol.
- **Swift 6, strict concurrency.** `Transaction.updates` is an `AsyncSequence` — the listener task's lifecycle and actor-isolation must be deliberate, not accidental (this plan's own history in Plan 6a shows exactly this class of bug is easy to get subtly wrong with Apple/Google SDKs — verify against Apple's actual current StoreKit 2 API rather than a guessed sketch, same discipline as Plan 6a).
- **App Store Server Notifications V2 verification must actually verify the JWS signature** — never trust an unverified webhook payload. Apple publishes their signing certificate chain; the Cloud Function must validate it (via Apple's own `app-store-server-library-node` or equivalent, not hand-rolled JWT parsing) before trusting anything in the payload.
- **This plan does not implement the route planner, "what's left" toggle, widgets, or notifications** — those are Plan 6b-2/6b-3, gated on this plan's `isProEntitled` but not built here.

---

## File Structure

```
NeonCompass/Core/Store/
  ProEntitlementProviding.swift     # protocol
  StoreKitProProvider.swift         # StoreKit 2-backed implementation

NeonCompass/Features/Store/
  ProEntitlementModel.swift          # @Observable, holds isProEntitled + purchase/restore actions
  PaywallView.swift                  # sheet: feature list, price, buy/restore buttons

NeonCompass/App/RootView.swift       # MODIFIED: constructs+injects ProEntitlementModel via .environment
NeonCompass/Features/Profile/ProfileScreen.swift  # MODIFIED: Pro badge + "Upgrade to Pro" entry point

NeonCompass/Features/Feed/FeedListView.swift       # MODIFIED: banner conditional on !isProEntitled
NeonCompass/Features/Cheats/CheatsListView.swift   # MODIFIED: banner conditional on !isProEntitled
NeonCompass/Features/Guides/GuidesListView.swift   # MODIFIED: banner conditional on !isProEntitled

functions/src/appStoreServerNotification.ts  # NEW: App Store Server Notifications V2 webhook
functions/package.json                        # MODIFIED: add app-store-server-library dependency

NeonCompass/Resources/Localizable.xcstrings   # MODIFIED: paywall/badge strings

docs/ops/2026-07-23-app-store-connect-iap.md  # NEW: manual App Store Connect steps (create the IAP product, configure the server-notifications endpoint)
```

---

### Task 1: `Core/Store/` protocol + StoreKit 2 provider

**Files:**
- Create: `NeonCompass/Core/Store/ProEntitlementProviding.swift`
- Create: `NeonCompass/Core/Store/StoreKitProProvider.swift`

**Interfaces:**
- Produces: `ProEntitlementProviding` protocol (`currentEntitlement() async -> Bool`, `purchase() async throws -> Bool` returning whether it's now entitled, `restorePurchases() async throws -> Bool`, `entitlementUpdates: AsyncStream<Bool>`) — consumed by Task 2's `ProEntitlementModel`.

- [ ] **Step 1: Verify the current StoreKit 2 API surface before writing anything**

Same discipline as every SDK-facing task in Plan 6a: use WebSearch/WebFetch to confirm the CURRENT StoreKit 2 API for this project's iOS 26 deployment target — `Product.products(for:)`, `Product.PurchaseResult`, `Transaction.currentEntitlements`, `Transaction.updates`, `VerificationResult<Transaction>`, `Transaction.finish()`, and `Product.PurchaseOption.appAccountToken(_:)`. StoreKit 2's Swift API has been stable since iOS 15 with incremental additions — confirm nothing material has changed for iOS 26, and confirm the exact unwrapping pattern for `VerificationResult` (`.verified`/`.unverified` cases) rather than guessing.

- [ ] **Step 2: Write `ProEntitlementProviding.swift`**

```swift
import Foundation

/// Abstraction over StoreKit 2 — the ONLY source of truth for whether this
/// user has purchased Pro (spec §"Pro": "L'entitlement StoreKit signé par
/// Apple est la source de vérité locale"). Never backed by a server call.
protocol ProEntitlementProviding: Sendable {
    /// Checks StoreKit's current entitlements right now (e.g. at launch).
    func currentEntitlement() async -> Bool

    /// Initiates the Pro purchase. Returns whether the app is now entitled
    /// (false if the user cancelled — not an error). Never requires the
    /// caller to be signed in.
    func purchase() async throws -> Bool

    /// Re-syncs entitlements from Apple (App Store Connect → "Restore
    /// Purchases" requirement, spec risk table "3.1.1 (IAP)").
    func restorePurchases() async throws -> Bool

    /// Live updates as StoreKit's own Transaction.updates stream reports
    /// entitlement changes (e.g. a refund, or a purchase completing after
    /// the app was backgrounded during Ask to Buy).
    var entitlementUpdates: AsyncStream<Bool> { get }
}
```

- [ ] **Step 3: Write `StoreKitProProvider.swift`**

Adapt this sketch to whatever your Step 1 research confirms about the exact API. The Pro product ID below (`co.antoineteston.neoncompass.pro`) matches this project's `bundleIdPrefix: co.antoineteston` from `project.yml` — confirm the exact final identifier once the real product is created in App Store Connect (Task 6's ops doc tracks this).

```swift
import StoreKit

/// Implémentation réelle de ProEntitlementProviding. Ne référence jamais
/// Firestore/FirebaseAuth — ce fichier ne fait que parler à StoreKit,
/// l'appelant (ProEntitlementModel) décide s'il faut aussi notifier le
/// serveur (Task 5, App Store Server Notifications V2, pas ici).
final class StoreKitProProvider: ProEntitlementProviding {
    static let proProductID = "co.antoineteston.neoncompass.pro"

    func currentEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.proProductID {
                return true
            }
        }
        return false
    }

    func purchase() async throws -> Bool {
        let products = try await Product.products(for: [Self.proProductID])
        guard let product = products.first else {
            throw ProEntitlementError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw ProEntitlementError.unverifiedTransaction
            }
            await transaction.finish()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restorePurchases() async throws -> Bool {
        try await AppStore.sync()
        return await currentEntitlement()
    }

    var entitlementUpdates: AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result, transaction.productID == Self.proProductID else { continue }
                    await transaction.finish()
                    continuation.yield(await currentEntitlement())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum ProEntitlementError: Error {
    case productNotFound
    case unverifiedTransaction
}
```

- [ ] **Step 4: Build to confirm it compiles**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`. (This requires `project.yml` to already link a `StoreKit` framework dependency — StoreKit is a system framework, not SPM, so no `project.yml` change should be needed; if the build fails on a missing StoreKit import, that's a signal to add an explicit `sdk: StoreKit.framework` dependency entry — check `project.yml`'s existing target dependencies for the pattern, though system frameworks are typically auto-linked and this step should just work.)

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Store/ProEntitlementProviding.swift NeonCompass/Core/Store/StoreKitProProvider.swift
git commit -m "feat: Core/Store protocol + StoreKit 2-backed Pro entitlement provider"
```

---

### Task 2: `ProEntitlementModel` shared via environment

**Files:**
- Create: `NeonCompass/Features/Store/ProEntitlementModel.swift`
- Create: `NeonCompassTests/Store/ProEntitlementFakesTests.swift`
- Modify: `NeonCompass/App/RootView.swift`

**Interfaces:**
- Produces: `ProEntitlementModel.isProEntitled: Bool`, `.purchase() async`, `.restorePurchases() async`, consumed by Task 3 (paywall), Task 4 (ad gating), and Plan 6b-2/6b-3's gated features.

- [ ] **Step 1: Write `ProEntitlementModel.swift`**

```swift
import Foundation
import Observation

@Observable
@MainActor
final class ProEntitlementModel {
    private(set) var isProEntitled = false

    private let provider: ProEntitlementProviding
    private var updatesTask: Task<Void, Never>?

    init(provider: ProEntitlementProviding) {
        self.provider = provider
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await isEntitled in provider.entitlementUpdates {
                self.isProEntitled = isEntitled
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        isProEntitled = await provider.currentEntitlement()
    }

    func purchase() async {
        isProEntitled = (try? await provider.purchase()) ?? isProEntitled
    }

    func restorePurchases() async {
        isProEntitled = (try? await provider.restorePurchases()) ?? isProEntitled
    }
}
```

- [ ] **Step 2: Write fakes + tests**

Follow the established `Fake*` convention (see `NeonCompassTests/Community/CommunityFakesTests.swift`/`NeonCompassTests/Onboarding/OnboardingFakesTests.swift` for the exact style: `nonisolated(unsafe) var` on the fake, a small self-test).

```swift
import Testing
@testable import NeonCompass

final class FakeProEntitlementProvider: ProEntitlementProviding {
    nonisolated(unsafe) var currentEntitlementToReturn = false
    nonisolated(unsafe) var purchaseResultToReturn: Result<Bool, Error> = .success(true)
    nonisolated(unsafe) var restoreResultToReturn: Result<Bool, Error> = .success(true)
    nonisolated(unsafe) private(set) var purchaseCallCount = 0
    nonisolated(unsafe) private(set) var restoreCallCount = 0

    func currentEntitlement() async -> Bool { currentEntitlementToReturn }

    func purchase() async throws -> Bool {
        purchaseCallCount += 1
        return try purchaseResultToReturn.get()
    }

    func restorePurchases() async throws -> Bool {
        restoreCallCount += 1
        return try restoreResultToReturn.get()
    }

    var entitlementUpdates: AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
struct ProEntitlementFakesTests {
    @Test func refreshReflectsCurrentEntitlement() async {
        let fake = FakeProEntitlementProvider()
        fake.currentEntitlementToReturn = true
        let model = ProEntitlementModel(provider: fake)

        await model.refresh()

        #expect(model.isProEntitled)
    }

    @Test func purchaseSetsEntitledOnSuccess() async {
        let fake = FakeProEntitlementProvider()
        fake.purchaseResultToReturn = .success(true)
        let model = ProEntitlementModel(provider: fake)

        await model.purchase()

        #expect(model.isProEntitled)
        #expect(fake.purchaseCallCount == 1)
    }

    @Test func purchaseLeavesStateUnchangedOnCancellation() async {
        let fake = FakeProEntitlementProvider()
        fake.purchaseResultToReturn = .success(false)
        let model = ProEntitlementModel(provider: fake)

        await model.purchase()

        #expect(!model.isProEntitled)
    }

    @Test func restorePurchasesReflectsRestoredEntitlement() async {
        let fake = FakeProEntitlementProvider()
        fake.restoreResultToReturn = .success(true)
        let model = ProEntitlementModel(provider: fake)

        await model.restorePurchases()

        #expect(model.isProEntitled)
        #expect(fake.restoreCallCount == 1)
    }
}
```

- [ ] **Step 3: Inject via `RootView.swift`**

Read the current file in full — it currently constructs `AuthModel` and injects it via `.environment(authModel)` (Plan 6a's fix). Add `ProEntitlementModel` the same way:

```swift
    @State private var authModel = AuthModel(authProvider: FirebaseAuthProvider())
    @State private var proEntitlementModel = ProEntitlementModel(provider: StoreKitProProvider())
```

```swift
        .environment(authModel)
        .environment(proEntitlementModel)
```

Add a `.task` to refresh on launch, alongside the existing consent/App-Check `.task`:

```swift
        .task {
            await proEntitlementModel.refresh()
        }
```

- [ ] **Step 4: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`, including the new `ProEntitlementFakesTests` suite.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Store/ProEntitlementModel.swift NeonCompassTests/Store/ProEntitlementFakesTests.swift NeonCompass/App/RootView.swift
git commit -m "feat: ProEntitlementModel, constructed once at RootView and shared via environment"
```

---

### Task 3: Paywall screen

**Files:**
- Create: `NeonCompass/Features/Store/PaywallView.swift`
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ProEntitlementModel` (Task 2), via `@Environment(ProEntitlementModel.self)`.

- [ ] **Step 1: Add Localizable.xcstrings entries**

Same pattern as every prior plan's string additions (single `en` localization, `state: translated`):

| Key | EN value |
|---|---|
| `paywall.title` | Neon Compass Pro |
| `paywall.subtitle` | Comfort and tools — never the facts. |
| `paywall.feature.ads` | No ads |
| `paywall.feature.sync` | Cloud sync between iPhone and iPad |
| `paywall.feature.route` | Optimized collectible route planner |
| `paywall.feature.remaining` | "What's left to do" map mode |
| `paywall.feature.widgets` | Home screen & Lock Screen widgets |
| `paywall.feature.notifications` | Followed-spot notifications |
| `paywall.feature.themes` | Exclusive app icons & themes |
| `paywall.buy` | Unlock Pro |
| `paywall.restore` | Restore Purchases |
| `paywall.close` | Close |
| `profile.pro.badge` | PRO |
| `profile.pro.upgradeButton` | Upgrade to Pro |

- [ ] **Step 2: Write `PaywallView.swift`**

```swift
import SwiftUI

struct PaywallView: View {
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.dismiss) private var dismiss

    private let features: [(LocalizedStringKey, String)] = [
        ("paywall.feature.ads", "nosign"),
        ("paywall.feature.sync", "icloud"),
        ("paywall.feature.route", "map"),
        ("paywall.feature.remaining", "checklist"),
        ("paywall.feature.widgets", "square.grid.2x2"),
        ("paywall.feature.notifications", "bell"),
        ("paywall.feature.themes", "paintpalette"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("paywall.title")
                        .font(NCTypography.displayTitle)
                        .foregroundStyle(NCColor.neonCyan)
                    Text("paywall.subtitle")
                        .font(NCTypography.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(features, id: \.1) { feature in
                            Label(feature.0, systemImage: feature.1)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))

                    if proEntitlementModel.isProEntitled {
                        Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(NCColor.neonCyan)
                    } else {
                        Button("paywall.buy") {
                            Task { await proEntitlementModel.purchase() }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(NCColor.sunsetMagenta)

                        Button("paywall.restore") {
                            Task { await proEntitlementModel.restorePurchases() }
                        }
                    }
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("paywall.close") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Wire into `ProfileScreen.swift`**

Read the current file in full. Add `@Environment(ProEntitlementModel.self) private var proEntitlementModel` and a `@State private var showPaywall = false`. In `signedInContent`/`signedOutContent` (the paywall should be reachable regardless of sign-in state, since purchase never requires an account — add it near the top of `body`, outside the `if let userID` branch), add:

```swift
    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 24) {
                if proEntitlementModel.isProEntitled {
                    Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(NCColor.neonCyan)
                } else {
                    Button("profile.pro.upgradeButton") { showPaywall = true }
                }
                if let userID = authModel.userID {
                    signedInContent(userID: userID)
                } else {
                    signedOutContent
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        // ... existing .task/.onAppear/.alert unchanged
    }
```

- [ ] **Step 4: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`.

- [ ] **Step 5: Manual smoke test**

Launch in the Simulator (StoreKit purchases in the Simulator use StoreKit's local testing configuration — if this project has no `.storekit` configuration file yet, note that as a gap for a human to set up in Xcode, not something to fix in this task). Confirm the paywall sheet opens from Profile, shows the 7 features, and the buy/restore buttons don't crash even without a real StoreKit config (they should fail gracefully — `Product.products(for:)` returning empty throws `ProEntitlementError.productNotFound`, caught by `purchase()`'s `try?`).

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Features/Store/PaywallView.swift NeonCompass/Features/Profile/ProfileScreen.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: Pro paywall sheet, reachable from Profile regardless of sign-in state"
```

---

### Task 4: Ad removal for entitled users

**Files:**
- Modify: `NeonCompass/Features/Feed/FeedListView.swift`
- Modify: `NeonCompass/Features/Cheats/CheatsListView.swift`
- Modify: `NeonCompass/Features/Guides/GuidesListView.swift`

**Interfaces:**
- Consumes: `ProEntitlementModel` (Task 2), `BannerAdView` (Plan 6a).

- [ ] **Step 1: Gate each banner**

In each of the three files, add `@Environment(ProEntitlementModel.self) private var proEntitlementModel` and wrap the existing `BannerAdView().frame(height: 50)` in a conditional:

```swift
                if !proEntitlementModel.isProEntitled {
                    BannerAdView()
                        .frame(height: 50)
                }
```

- [ ] **Step 2: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add NeonCompass/Features/Feed/FeedListView.swift NeonCompass/Features/Cheats/CheatsListView.swift NeonCompass/Features/Guides/GuidesListView.swift
git commit -m "feat: hide ad banners for Pro-entitled users"
```

---

### Task 5: App Store Server Notifications V2 → `profiles/{uid}.isPremium` mirror

**Files:**
- Create: `functions/src/appStoreServerNotification.ts`
- Modify: `functions/package.json`
- Modify: `functions/src/index.ts`

**Interfaces:** none consumed by later tasks — this is a best-effort, badge-only mirror, deliberately not read by any gating logic.

- [ ] **Step 1: Add the App Store Server Library dependency**

```bash
cd functions && npm install @apple/app-store-server-library
```

(Verify this exact package name via WebSearch — Apple publishes an official Node.js library for verifying/parsing App Store Server Notifications V2 JWS payloads; confirm the current package name and API before writing Step 2, same discipline as every SDK-facing task in this plan and Plan 6a.)

- [ ] **Step 2: Write `appStoreServerNotification.ts`**

```typescript
// functions/src/appStoreServerNotification.ts
import { onRequest } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
// Verify the exact import path/API against the installed
// @apple/app-store-server-library version — this sketch is unverified
// against the actual package, per this task's Step 1.
import { SignedDataVerifier } from '@apple/app-store-server-library';

// Best-effort account badge mirror ONLY — never read by any client-side
// or server-side gating logic (see this plan's Global Constraints). If
// this function is ever down/misconfigured, the worst outcome is a stale
// badge, never a broken feature — the StoreKit entitlement on-device is
// unaffected.
export const appStoreServerNotification = onRequest({ region: 'europe-west1' }, async (req, res) => {
  const signedPayload = req.body?.signedPayload;
  if (typeof signedPayload !== 'string') {
    res.status(400).send('missing signedPayload');
    return;
  }

  // Verify the JWS signature against Apple's certificate chain before
  // trusting anything in the payload — never parse an unverified JWT.
  const verifier = new SignedDataVerifier(/* Apple root certs, bundle ID, environment — configure per the library's actual API */);
  let decodedPayload;
  try {
    decodedPayload = await verifier.verifyAndDecodeNotification(signedPayload);
  } catch (error) {
    res.status(400).send('invalid signature');
    return;
  }

  const transactionInfo = decodedPayload.data?.signedTransactionInfo;
  const appAccountToken = transactionInfo?.appAccountToken;
  const isEntitled = ['SUBSCRIBED', 'DID_RENEW'].includes(decodedPayload.subtype ?? '')
    || decodedPayload.notificationType === 'ONE_TIME_CHARGE';

  if (!appAccountToken) {
    // Purchase made without being signed in — nothing to mirror, not an
    // error (spec: "L'achat ne requiert jamais de connexion").
    res.status(200).send('no account token, ignored');
    return;
  }

  const db = getFirestore();
  const matching = await db.collection('profiles').where('appAccountToken', '==', appAccountToken).limit(1).get();
  if (!matching.empty) {
    await matching.docs[0].ref.update({ isPremium: isEntitled });
  }

  res.status(200).send('ok');
});
```

- [ ] **Step 3: Export from `index.ts`**

```typescript
export { appStoreServerNotification } from './appStoreServerNotification.js';
```

- [ ] **Step 4: Run tests**

Run: `cd functions && npm test`
Expected: existing tests still pass (this function has no pure-logic unit test of its own — it's a webhook handler requiring Apple's real signed payloads to test meaningfully, consistent with how this codebase doesn't unit-test its other webhook-style entry points either).

- [ ] **Step 5: Commit**

```bash
git add functions/src/appStoreServerNotification.ts functions/src/index.ts functions/package.json functions/package-lock.json
git commit -m "feat: App Store Server Notifications V2 webhook, mirrors Pro entitlement to profiles/{uid}.isPremium for the account badge only"
```

---

### Task 6: Ops doc — App Store Connect IAP setup

**Files:**
- Create: `docs/ops/2026-07-23-app-store-connect-iap.md`

- [ ] **Step 1: Write the ops doc**

```markdown
# App Store Connect: In-App Purchase & Server Notifications setup (manual steps)

Not expressible in code — App Store Connect configuration. Spec §"Pro":
"achat unique ~5-6 €, StoreKit 2".

## 1. Create the Pro IAP product

1. App Store Connect → this app → In-App Purchases → Create.
2. Type: Non-Consumable.
3. Product ID: `co.antoineteston.neoncompass.pro` (must match
   `StoreKitProProvider.proProductID` exactly — update both if this
   changes).
4. Price: ~5-6 € tier (spec-suggested range).
5. Add a `.storekit` local testing configuration in Xcode (Product Data →
   New File → StoreKit Configuration) with a matching test product, so the
   paywall can be exercised in the Simulator without a live App Store
   Connect roundtrip.

## 2. Configure App Store Server Notifications V2

1. App Store Connect → this app → App Information → App Store Server
   Notifications.
2. Version: V2.
3. Production/Sandbox URL: the deployed `appStoreServerNotification`
   Cloud Function's HTTPS trigger URL (`https://europe-west1-<project>.
   cloudfunctions.net/appStoreServerNotification`).

## 3. Link a purchase to an account (opt-in, badge only)

`appAccountToken` must be attached client-side at purchase time for the
server mirror to work — Task 5's webhook does nothing without it, by
design. This is not yet wired into `StoreKitProProvider.purchase()` in
this plan (see the plan's own scope — the current implementation calls
`product.purchase()` with no purchase options). If the account badge
mirror needs to actually work end-to-end, a follow-up must add:
`product.purchase(options: [.appAccountToken(profileUUID)])`, where
`profileUUID` is a UUID stored on the profile doc at creation time
(`createUserProfile`, Plan 5) — cross-reference against Task 5's Firestore
query (`where('appAccountToken', '==', ...)`) which expects this field to
already exist. **This is a real gap between Task 5's webhook and the
client's purchase call — flagging it here rather than silently shipping
half the mirror.**
```

- [ ] **Step 2: Commit**

```bash
git add docs/ops/2026-07-23-app-store-connect-iap.md
git commit -m "docs: App Store Connect IAP + Server Notifications setup checklist"
```

---

## Self-Review

**Spec coverage:**
- "achat unique ~5-6 €, StoreKit 2" — Tasks 1-3. ✅
- "Suppression des pubs" — Task 4. ✅
- "L'entitlement StoreKit... source de vérité locale ; le compte n'en est qu'un miroir serveur" — Tasks 1 (local), 5 (mirror). ✅
- "L'achat ne requiert jamais de connexion" — `purchase()`/`restorePurchases()` take no user identifier, work identically signed-in or not. ✅
- "Restaurer les achats" (spec risk table "3.1.1 (IAP)") — Task 3's paywall has a visible restore button. ✅
- Route planner, "reste à faire", widgets, notifications, themes/icons — explicitly out of scope, Plan 6b-2/6b-3.

**Known gap, disclosed not silently shipped:** Task 6's ops doc explicitly flags that Task 5's App Store Server Notifications webhook expects an `appAccountToken` the client-side purchase call in Task 1 doesn't yet attach — the account badge mirror is scaffolded but not fully wired end-to-end in this plan. This is deliberate: attaching `appAccountToken` requires a `profileUUID` field on the profile doc that doesn't exist yet (a small addition to `createUserProfile.ts`, Plan 5), and wiring it correctly touches both the Cloud Functions and Swift sides in a way that's cleaner as a small, focused follow-up once this plan's core (local entitlement + paywall + ad removal — the parts that don't need an account at all) is verified working, rather than risking a half-tested three-way (client/webhook/Firestore-query) linkage in the same pass.
