# Plan 6b-2 — Pro features on existing infra (cloud sync, route planner, reste-à-faire, thèmes) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the four Pro features that reuse existing Map/Progression/Core infrastructure rather than requiring new platform capabilities — cloud sync of progression between iPhone and iPad, an optimized collectible route planner, a "what's left to do" map mode, and exclusive app icons/themes. Second sub-plan of "StoreKit 2 Pro" (roadmap Plan 6b, split into Core / Simple Features / Widgets+Notifications per product decision 2026-07-23). Everything here gates on `ProEntitlementModel.isProEntitled` from Plan 6b-1 — nothing here re-implements or duplicates that check's plumbing.

**Architecture:** Cloud sync adds two fields (`updatedAt: Date`) to the existing `FoundEntry`/`TrophyProgress` SwiftData models and a new `Core/Sync/` layer (protocol + Firestore-backed implementation) doing simple last-write-wins-per-item reconciliation — no CRDT, no operational transform, just a timestamp comparison, matching the actual complexity this feature needs (a handful of boolean toggles, not a collaborative document). The route planner is a pure, unit-tested greedy nearest-neighbor function consuming already-loaded `POI`/`NormalizedPoint` data — no new content pipeline. "What's left to do" is a filter toggle on `MapModel`. Themes/icons reuse `NCColor` and `UIApplication.setAlternateIconName`.

**Tech Stack:** SwiftData (schema addition), Firestore (a new `progression` subcollection per profile), StoreKit-gated UI (Plan 6b-1's `ProEntitlementModel`), `UIApplication.setAlternateIconName`.

## Global Constraints

- **Every feature in this plan gates on `ProEntitlementModel.isProEntitled`**, consumed via `@Environment(ProEntitlementModel.self)` — never re-check StoreKit directly, never construct a second entitlement instance (Plan 6a's `AuthModel` and Plan 6b-1's `ProEntitlementModel` both already established "one shared instance via environment" as the only correct pattern in this codebase).
- **Cloud sync requires BOTH Pro AND signed in** — the spec explicitly ties this feature to having an account ("Sync cloud de la progression iPhone↔iPad (nécessite le compte)"), unlike every other Pro feature in this plan, which need only the entitlement. Gate on `proEntitlementModel.isProEntitled && authModel.userID != nil`.
- **Sync is last-write-wins per item, using each item's own `updatedAt` timestamp** — never a full-collection overwrite in either direction (that would silently erase whichever device's timestamp is older, including legitimate un-toggling). No conflict UI, no merge prompts — the timestamp comparison is the entire conflict resolution strategy, and that is a deliberate, disclosed simplification (see Self-Review), not an oversight.
- **Sync failure must never block local functionality.** Every sync call is fire-and-forget/best-effort (`try?`) — a network failure, a signed-out state, or a non-Pro user must never prevent `toggleFound`/`toggleTrophy` from working locally exactly as they did before this plan.
- **Firebase stays behind protocols in `Core/`** — `Core/Sync/` mirrors every other `Core/*` layer's convention.
- **Route planner never claims to solve TSP optimally** — spec explicitly says "tri glouton" (greedy sort), not an optimal solver. Don't over-engineer this into a real traveling-salesman solution; a simple nearest-neighbor greedy walk is the spec'd behavior.
- **"What's left to do" hides, never deletes.** Toggling the mode off must restore every hidden POI exactly as it was — it's a view filter, not a data mutation.
- **Themes/icons are cosmetic only** — spec explicitly excludes anything that could look like "pay to win" (no XP, no cheat unlocks). Exclusive icons/themes are the correct scope; don't scope-creep into anything gameplay-adjacent.
- **Swift 6 strict concurrency**, matching every established pattern in this codebase (`nonisolated(unsafe)` for SDK handles, `@MainActor` where UI-thread execution is required — verify against actual API behavior rather than assuming, per this project's established discipline across Plans 6a/6b-1).
- **This plan does not implement widgets or followed notifications** — those are Plan 6b-3.

---

## File Structure

```
NeonCompass/Core/DesignSystem/FoundEntry.swift     # find actual current location — MODIFIED: add updatedAt
NeonCompass/Core/DesignSystem/TrophyProgress.swift  # find actual current location — MODIFIED: add updatedAt
NeonCompass/App/NeonCompassApp.swift                # MODIFIED: schema migration note if needed (see Task 1)

NeonCompass/Core/Sync/
  ProgressionSyncing.swift          # protocol
  FirestoreProgressionSync.swift    # Firestore-backed implementation

NeonCompass/Features/Map/MapModel.swift            # MODIFIED: upload on toggleFound, reste-à-faire filter
NeonCompass/Features/Progression/ProgressionModel.swift  # MODIFIED: upload on toggleTrophy, pull/reconcile on load
NeonCompass/Features/Map/MapScreen.swift            # MODIFIED: reste-à-faire toggle UI, route planner UI
NeonCompass/Features/Progression/ProgressionScreen.swift  # MODIFIED: sync trigger on appear

NeonCompass/Core/Map/RoutePlanner.swift              # NEW: pure greedy nearest-neighbor algorithm
NeonCompassTests/Map/RoutePlannerTests.swift          # NEW

NeonCompass/Features/Profile/ProfileScreen.swift      # MODIFIED: icon/theme picker entry point
NeonCompass/Features/Profile/ThemeStore.swift         # NEW: @Observable, current theme + alternate icon selection
NeonCompass/Core/DesignSystem/NCTheme.swift           # NEW: the small set of selectable accent palettes

NeonCompass/Resources/Localizable.xcstrings           # MODIFIED: new strings

docs/ops/2026-07-23-alternate-app-icons.md            # NEW: manual Xcode/App Store Connect steps for alternate icons
```

---

### Task 1: Cloud sync infra — schema + `Core/Sync/` + upload-on-toggle

**Files:**
- Modify: the actual current files defining `FoundEntry`/`TrophyProgress` (locate via `find NeonCompass -iname "FoundEntry.swift" -o -iname "TrophyProgress.swift"` — this plan's file-structure header above is a guess, confirm the real paths before editing)
- Create: `NeonCompass/Core/Sync/ProgressionSyncing.swift`
- Create: `NeonCompass/Core/Sync/FirestoreProgressionSync.swift`
- Modify: `NeonCompass/Features/Map/MapModel.swift`
- Modify: `NeonCompass/Features/Progression/ProgressionModel.swift`

**Interfaces:**
- Produces: `ProgressionSyncing` protocol (`func upload(itemID: String, kind: ProgressionItemKind, found: Bool, updatedAt: Date) async`, `func fetchAll() async -> [ProgressionSyncItem]` where `ProgressionSyncItem` is `{itemID: String, kind: ProgressionItemKind, found: Bool, updatedAt: Date}`, `ProgressionItemKind: String, Codable { case poi, trophy }`) — consumed by Task 2 (the pull/reconcile side, wired into the screens).

- [ ] **Step 1: Locate and read the current `FoundEntry`/`TrophyProgress` SwiftData models in full**

```bash
find NeonCompass -iname "FoundEntry.swift" -o -iname "TrophyProgress.swift"
```

- [ ] **Step 2: Add `updatedAt` to both models**

`FoundEntry` already has `foundAt: Date` — this IS the update timestamp for a POI (a found POI's "found-ness" never changes after the fact in today's UI, only gets created/deleted — but deletion, i.e. un-marking, needs its own timestamp to compare against a remote write). Rather than overload `foundAt`'s meaning, add a separate field so `foundAt` keeps meaning "when first found" (a small but real user-facing fact worth preserving) while sync gets its own clock:

```swift
@Model
final class FoundEntry {
    @Attribute(.unique) var poiID: String
    var foundAt: Date
    var updatedAt: Date = Date.now // new — SwiftData default value handles migration for existing rows

    init(poiID: String, foundAt: Date = .now, updatedAt: Date = .now) {
        self.poiID = poiID
        self.foundAt = foundAt
        self.updatedAt = updatedAt
    }
}
```

`TrophyProgress` has no timestamp at all — add one the same way:

```swift
@Model
final class TrophyProgress {
    @Attribute(.unique) var trophyID: String
    var updatedAt: Date = Date.now // new

    init(trophyID: String, updatedAt: Date = .now) {
        self.trophyID = trophyID
        self.updatedAt = updatedAt
    }
}
```

A default value on a new `@Model` property is SwiftData's standard lightweight-migration mechanism (no explicit migration plan needed for adding an optional-with-default field) — verify this compiles and existing tests still pass with no migration errors; if SwiftData surfaces a migration issue, that's real information to report back, not something to route around silently.

- [ ] **Step 3: Write `ProgressionSyncing.swift`**

```swift
import Foundation

enum ProgressionItemKind: String, Codable, Sendable {
    case poi, trophy
}

struct ProgressionSyncItem: Sendable {
    let itemID: String
    let kind: ProgressionItemKind
    let found: Bool
    let updatedAt: Date
}

/// Abstraction over the Firestore-backed progression mirror. Cloud sync is
/// Pro + signed-in only (spec: "nécessite le compte") — every caller must
/// check both `ProEntitlementModel.isProEntitled` and `AuthModel.userID`
/// before calling this at all; this protocol itself has no opinion on
/// entitlement or auth state, it just moves data once asked to.
protocol ProgressionSyncing: Sendable {
    func upload(itemID: String, kind: ProgressionItemKind, found: Bool, updatedAt: Date) async
    func fetchAll(uid: String) async -> [ProgressionSyncItem]
}
```

- [ ] **Step 4: Write `FirestoreProgressionSync.swift`**

```swift
import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Implémentation réelle de ProgressionSyncing. Écrit sous
/// profiles/{uid}/progression/{kind}_{itemID} — un document par item, pas
/// un blob unique, pour que le dernier-écrivain-gagne se fasse par item
/// (voir ce plan, Global Constraints) plutôt que d'écraser tout l'historique
/// d'un appareil si l'autre appareil était hors-ligne plus longtemps.
final class FirestoreProgressionSync: ProgressionSyncing {
    nonisolated(unsafe) private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func upload(itemID: String, kind: ProgressionItemKind, found: Bool, updatedAt: Date) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docID = "\(kind.rawValue)_\(itemID)"
        try? await firestore.collection("profiles").document(uid).collection("progression").document(docID).setData([
            "itemID": itemID,
            "kind": kind.rawValue,
            "found": found,
            "updatedAt": Timestamp(date: updatedAt),
        ])
    }

    func fetchAll(uid: String) async -> [ProgressionSyncItem] {
        guard let snapshot = try? await firestore.collection("profiles").document(uid).collection("progression").getDocuments() else {
            return []
        }
        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let itemID = data["itemID"] as? String,
                  let kindRaw = data["kind"] as? String,
                  let kind = ProgressionItemKind(rawValue: kindRaw),
                  let found = data["found"] as? Bool,
                  let timestamp = data["updatedAt"] as? Timestamp else {
                return nil
            }
            return ProgressionSyncItem(itemID: itemID, kind: kind, found: found, updatedAt: timestamp.dateValue())
        }
    }
}
```

Note: this reads `data["updatedAt"] as? Timestamp` directly from the document dict returned by `getDocuments()`'s snapshot, NOT via `JSONSerialization` — confirm this is how `QueryDocumentSnapshot.data()` actually behaves (it returns a `[String: Any]` with native Firestore types like `Timestamp` already resolved, not raw JSON) before treating this as safe; this is the same `Timestamp`-handling caution as every other Firestore-reading file in this codebase (`FirestoreProfileRepository`, `FirestoreContributionRepository`), but here the field is read via plain dictionary access rather than `document.data(as:)` Codable decoding — verify this specific access pattern (`as? Timestamp` on a `.data()` dictionary value) is genuinely safe and doesn't hit the `JSONSerialization` trap those other files were fixed to avoid. If your research finds any risk here, prefer `document.data(as: SomeCodableStruct.self)` instead, matching the established safe pattern.

- [ ] **Step 5: Add a Firestore Security Rule for the new subcollection**

Read the current `firestore.rules` in full. Add, alongside the existing `profiles/{uid}` rule:

```
    match /profiles/{uid}/progression/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
```

This is a genuine exception to this codebase's "client never writes directly" convention used for `contributions`/`votes` — progression sync is pure personal data with no community/moderation surface, so direct owner read/write is the correct, simplest rule (no Cloud Function needed to broker a user writing their own device's toggle state).

- [ ] **Step 6: Wire upload calls into `MapModel.toggleFound` and `ProgressionModel.toggleTrophy`**

Read both files in full (current versions, from Plans 2/4). Add a `sync: ProgressionSyncing?` parameter to each model's initializer (optional, defaulting to `nil` so existing call sites and tests aren't broken — the screens will pass a real instance only when Pro+signed-in, see Task 2). In `toggleFound`:

```swift
    func toggleFound(_ poi: POI) {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        let now = Date.now
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            foundPOIIDs.remove(poiID)
            try? modelContext.save()
            Task { await sync?.upload(itemID: poiID, kind: .poi, found: false, updatedAt: now) }
        } else {
            modelContext.insert(FoundEntry(poiID: poi.id, updatedAt: now))
            foundPOIIDs.insert(poiID)
            try? modelContext.save()
            Task { await sync?.upload(itemID: poiID, kind: .poi, found: true, updatedAt: now) }
        }
    }
```

Same pattern for `ProgressionModel.toggleTrophy` with `kind: .trophy`.

- [ ] **Step 7: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **` (this confirms the SwiftData schema change migrates cleanly).
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **` (no new tests required for this step — the upload call is fire-and-forget and untestable without a live/emulated Firestore, consistent with how `FirestoreContentRepository`/`FirestoreContributionRepository` have no dedicated unit tests either; Task 2 adds the reconciliation logic, which IS pure/testable).

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Core/Sync/ProgressionSyncing.swift NeonCompass/Core/Sync/FirestoreProgressionSync.swift NeonCompass/Features/Map/MapModel.swift NeonCompass/Features/Progression/ProgressionModel.swift firestore.rules
git add <the actual FoundEntry.swift and TrophyProgress.swift paths found in Step 1>
git commit -m "feat: progression cloud sync infra (Core/Sync, updatedAt timestamps, upload-on-toggle)"
```

---

### Task 2: Pull/reconcile on launch + screen wiring

**Files:**
- Modify: `NeonCompass/Features/Map/MapModel.swift`
- Modify: `NeonCompass/Features/Progression/ProgressionModel.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Features/Progression/ProgressionScreen.swift`
- Create: `NeonCompassTests/Sync/ProgressionReconciliationTests.swift`

**Interfaces:**
- Produces: `MapModel.reconcile(with: [ProgressionSyncItem])`/`ProgressionModel.reconcile(with: [ProgressionSyncItem])` — pure reconciliation logic, unit-testable independent of Firestore.

- [ ] **Step 1: Add a pure reconciliation method to `MapModel`**

The reconciliation rule: for each remote `ProgressionSyncItem` of kind `.poi`, if the remote's `found` state differs from local AND the remote `updatedAt` is strictly newer than the local `FoundEntry`'s `updatedAt` (or no local entry exists and remote says found), apply the remote state locally (insert or delete `FoundEntry`, using the REMOTE `updatedAt`, not `.now` — preserving the actual timestamp so a later reconciliation pass has an accurate basis for comparison). If local doesn't exist and remote says NOT found, no-op (nothing to create for an absence). If local exists and is newer than or equal to remote, local wins, do nothing (an equal timestamp is treated as "local already has this," not re-applied, to avoid a redundant delete+reinsert flip-flop):

```swift
    func reconcile(with remoteItems: [ProgressionSyncItem]) {
        for item in remoteItems where item.kind == .poi {
            let poiID = item.itemID
            let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
            let existing = try? modelContext.fetch(descriptor).first

            if let existing, existing.updatedAt >= item.updatedAt {
                continue // local is at least as recent, local wins
            }

            if item.found {
                if let existing {
                    existing.updatedAt = item.updatedAt
                } else {
                    modelContext.insert(FoundEntry(poiID: poiID, foundAt: item.updatedAt, updatedAt: item.updatedAt))
                }
                foundPOIIDs.insert(poiID)
            } else if let existing {
                modelContext.delete(existing)
                foundPOIIDs.remove(poiID)
            }
        }
        try? modelContext.save()
    }
```

Add the analogous `reconcile(with:)` to `ProgressionModel` for `kind == .trophy`, using `TrophyProgress`/`checkedTrophyIDs` instead.

- [ ] **Step 2: Write `ProgressionReconciliationTests.swift`**

Test the pure reconciliation logic against an in-memory `ModelContainer` (same pattern as `CommunityFakesTests`/`ProEntitlementFakesTests` — `ModelConfiguration(isStoredInMemoryOnly: true)`):

```swift
import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct ProgressionReconciliationTests {
    private func makeModel() throws -> (MapModel, ModelContext) {
        let container = try ModelContainer(for: FoundEntry.self, PersonalPin.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let model = MapModel(pois: [], modelContext: context)
        return (model, context)
    }

    @Test func reconcileAppliesANewerRemoteFoundState() throws {
        let (model, _) = try makeModel()
        let newer = Date.now
        model.reconcile(with: [ProgressionSyncItem(itemID: "poi-1", kind: .poi, found: true, updatedAt: newer)])
        #expect(model.isFound(POI(id: "poi-1", category: .landmark, position: nil, title: LocalizedText(en: "x", fr: nil, es: nil, it: nil, de: nil), note: nil)))
    }

    @Test func reconcileIgnoresAnOlderRemoteState() throws {
        let (model, context) = try makeModel()
        let now = Date.now
        context.insert(FoundEntry(poiID: "poi-1", foundAt: now, updatedAt: now))
        try context.save()
        let older = now.addingTimeInterval(-60)
        model.reconcile(with: [ProgressionSyncItem(itemID: "poi-1", kind: .poi, found: false, updatedAt: older)])
        // local (found=true, now) is newer than remote (found=false, older) — local wins
        #expect(model.isFound(POI(id: "poi-1", category: .landmark, position: nil, title: LocalizedText(en: "x", fr: nil, es: nil, it: nil, de: nil), note: nil)))
    }

    @Test func reconcileAppliesANewerRemoteUnfoundState() throws {
        let (model, context) = try makeModel()
        let older = Date.now.addingTimeInterval(-120)
        context.insert(FoundEntry(poiID: "poi-1", foundAt: older, updatedAt: older))
        try context.save()
        let newer = Date.now
        model.reconcile(with: [ProgressionSyncItem(itemID: "poi-1", kind: .poi, found: false, updatedAt: newer)])
        #expect(!model.isFound(POI(id: "poi-1", category: .landmark, position: nil, title: LocalizedText(en: "x", fr: nil, es: nil, it: nil, de: nil), note: nil)))
    }
}
```

(Adjust `POI`/`LocalizedText` construction to match their actual current initializers — read `NeonCompass/Features/Map/POI.swift` first, this plan's sketch may not match the exact current signature.)

- [ ] **Step 3: Wire into `MapScreen.swift`/`ProgressionScreen.swift`**

Read both files in full. In each screen's model-construction point (`loadModel()`/equivalent), construct `FirestoreProgressionSync()` only when `authModel.userID != nil && proEntitlementModel.isProEntitled` (both already injected via `@Environment` from Plans 6a/6b-1), pass it into the model's `sync:` parameter, and — only in that same condition — call `await sync.fetchAll(uid: userID)` then `model.reconcile(with:)` inside the existing loading `Task`.

- [ ] **Step 4: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`, including the new `ProgressionReconciliationTests` suite.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Map/MapModel.swift NeonCompass/Features/Progression/ProgressionModel.swift NeonCompass/Features/Map/MapScreen.swift NeonCompass/Features/Progression/ProgressionScreen.swift NeonCompassTests/Sync/ProgressionReconciliationTests.swift
git commit -m "feat: pull/reconcile progression sync on launch, gated on Pro + signed-in"
```

---

### Task 3: Route planner

**Files:**
- Create: `NeonCompass/Core/Map/RoutePlanner.swift`
- Create: `NeonCompassTests/Map/RoutePlannerTests.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `RoutePlanner.greedyRoute(from remaining: [POI]) -> [POI]` (pure, unit-tested) — consumed by a new Map UI element drawing the ordered route.

- [ ] **Step 1: Write `RoutePlanner.swift`**

```swift
import Foundation

/// Greedy nearest-neighbor tour over remaining (not-yet-found) collectibles
/// — spec explicitly calls for "tri glouton sur les coordonnées
/// normalisées," not an optimal TSP solve. Starts from the first item in
/// `remaining` (arbitrary but deterministic — callers control ordering by
/// what they pass in) and repeatedly picks the nearest not-yet-visited
/// point by Euclidean distance in normalized [0,1] map coordinates.
enum RoutePlanner {
    static func greedyRoute(from remaining: [POI]) -> [POI] {
        var unvisited = remaining.filter { $0.position != nil }
        guard !unvisited.isEmpty else { return [] }

        var route: [POI] = [unvisited.removeFirst()]
        while !unvisited.isEmpty {
            let current = route.last!.position!
            let nearestIndex = unvisited.indices.min { lhs, rhs in
                distance(current, unvisited[lhs].position!) < distance(current, unvisited[rhs].position!)
            }!
            route.append(unvisited.remove(at: nearestIndex))
        }
        return route
    }

    private static func distance(_ a: NormalizedPoint, _ b: NormalizedPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
```

- [ ] **Step 2: Write `RoutePlannerTests.swift`**

```swift
import Testing
@testable import NeonCompass

struct RoutePlannerTests {
    private func poi(_ id: String, _ x: Double, _ y: Double) -> POI {
        POI(id: id, category: .collectible, position: NormalizedPoint(x: x, y: y), title: LocalizedText(en: id, fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func greedyRouteVisitsEveryPOIExactlyOnce() {
        let pois = [poi("a", 0, 0), poi("b", 1, 1), poi("c", 0.5, 0.5)]
        let route = RoutePlanner.greedyRoute(from: pois)
        #expect(Set(route.map(\.id)) == Set(pois.map(\.id)))
        #expect(route.count == pois.count)
    }

    @Test func greedyRoutePicksTheNearestUnvisitedNext() {
        // Starting at (0,0): nearest is (0.1,0.1), then the far one (1,1) — not the reverse.
        let pois = [poi("start", 0, 0), poi("far", 1, 1), poi("near", 0.1, 0.1)]
        let route = RoutePlanner.greedyRoute(from: pois)
        #expect(route.map(\.id) == ["start", "near", "far"])
    }

    @Test func greedyRouteSkipsPOIsWithNoPosition() {
        let noPosition = POI(id: "pending", category: .collectible, position: nil, title: LocalizedText(en: "pending", fr: nil, es: nil, it: nil, de: nil), note: nil)
        let route = RoutePlanner.greedyRoute(from: [poi("a", 0, 0), noPosition])
        #expect(route.map(\.id) == ["a"])
    }

    @Test func greedyRouteOfEmptyInputIsEmpty() {
        #expect(RoutePlanner.greedyRoute(from: []).isEmpty)
    }
}
```

(Confirm `POI`'s actual initializer signature against the current file before finalizing — this plan's sketch may not match exactly.)

- [ ] **Step 3: Add Localizable.xcstrings entries**

| Key | EN value |
|---|---|
| `map.routePlanner.button` | Plan route |
| `map.routePlanner.title` | Optimized route |
| `map.routePlanner.empty` | Everything's found — nothing left to route! |
| `map.routePlanner.stepFormat` | Stop %d |

- [ ] **Step 4: Wire a route-planner UI element into `MapScreen.swift`**

Read the current file in full. Add, gated on `proEntitlementModel.isProEntitled`, a button (near the existing personal-pins button in `mapCanvas`) that computes `RoutePlanner.greedyRoute(from: model.filteredPOIs.filter { $0.category == .collectible && !model.isFound($0) })` and shows the result as a numbered list sheet (simplest correct UI for this plan — a full route-drawing polyline overlay on the tiled map is a nice-to-have, not required by the spec's "planificateur d'itinéraire" wording, which is about ordering, not necessarily a drawn line; if you have time and it's low-risk, a polyline overlay is a reasonable enhancement, but the numbered-list sheet alone satisfies the spec).

- [ ] **Step 5: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`, including the new `RoutePlannerTests` suite.

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Core/Map/RoutePlanner.swift NeonCompassTests/Map/RoutePlannerTests.swift NeonCompass/Features/Map/MapScreen.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: Pro route planner (greedy nearest-neighbor over remaining collectibles)"
```

---

### Task 4: "What's left to do" map mode

**Files:**
- Modify: `NeonCompass/Features/Map/MapModel.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `MapModel.hideFoundPOIs: Bool` — filters `filteredPOIs`.

- [ ] **Step 1: Add the toggle to `MapModel`**

```swift
    var hideFoundPOIs = false
```

Update `filteredPOIs`' existing filter chain to also exclude found POIs when the toggle is on:

```swift
    var filteredPOIs: [POI] {
        let languageCode = currentLanguageCode
        return pois.filter { poi in
            poi.position != nil
                && activeCategories.contains(poi.category)
                && !(hideFoundPOIs && isFound(poi))
                && (searchQuery.isEmpty
                    || poi.title.resolved(for: languageCode).localizedCaseInsensitiveContains(searchQuery))
        }
    }
```

- [ ] **Step 2: Add the Localizable.xcstrings entry**

| Key | EN value |
|---|---|
| `map.hideFound.toggle` | Show only what's left |

- [ ] **Step 3: Wire a toggle button into `MapScreen.swift`**, gated on `proEntitlementModel.isProEntitled` — a simple toggle button alongside the existing filter controls (`MapFilterControls`) is sufficient; read the current file to find the natural placement.

- [ ] **Step 4: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Map/MapModel.swift NeonCompass/Features/Map/MapScreen.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: Pro \"what's left to do\" map mode (hides already-found POIs)"
```

---

### Task 5: Exclusive icons & themes + profile polish

**Files:**
- Create: `NeonCompass/Core/DesignSystem/NCTheme.swift`
- Create: `NeonCompass/Features/Profile/ThemeStore.swift`
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`
- Modify: `project.yml`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`
- Create: `docs/ops/2026-07-23-alternate-app-icons.md`

**Interfaces:** none consumed by later plans — this is the leaf feature.

- [ ] **Step 1: Write `NCTheme.swift`**

A small, fixed set of accent-color alternatives, reusing existing `NCColor` hexes plus a couple of new original ones (never referencing any GTA/Rockstar palette by name):

```swift
import SwiftUI

enum NCTheme: String, CaseIterable, Identifiable {
    case magentaDrift
    case cyanPulse
    case sunsetOverdrive

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .magentaDrift: NCColor.sunsetMagenta
        case .cyanPulse: NCColor.neonCyan
        case .sunsetOverdrive: NCColor.sunsetOrange
        }
    }

    var nameKey: LocalizedStringKey {
        switch self {
        case .magentaDrift: "theme.magentaDrift"
        case .cyanPulse: "theme.cyanPulse"
        case .sunsetOverdrive: "theme.sunsetOverdrive"
        }
    }
}
```

- [ ] **Step 2: Write `ThemeStore.swift`**

```swift
import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ThemeStore {
    private static let themeKey = "selectedTheme"
    private let defaults: UserDefaults

    private(set) var selectedTheme: NCTheme

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.themeKey).flatMap(NCTheme.init(rawValue:))
        self.selectedTheme = stored ?? .magentaDrift
    }

    func selectTheme(_ theme: NCTheme) {
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: Self.themeKey)
    }

    func setAlternateIcon(named name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(name) { _ in }
    }
}
```

- [ ] **Step 3: Add alternate icon assets and `project.yml` configuration**

This step requires actual icon image assets, which this plan cannot generate. Add the `project.yml` wiring assuming at least one alternate icon asset named `AppIcon-Neon` exists in `NeonCompass/Resources/Assets.xcassets` — if it doesn't exist yet, note this clearly in your report as a human follow-up (a designer/asset-creation task, not a code task) rather than inventing a placeholder image asset. Research XcodeGen's mechanism for declaring `CFBundleIcons~ipad`/`CFBundleAlternateIcons` (likely via the same `INFOPLIST_FILE`-merge mechanism Plan 6a's Task 1 established for `GADApplicationIdentifier`, or XcodeGen's dedicated icon-set support if it has one — verify rather than guess).

- [ ] **Step 4: Wire theme/icon pickers into `ProfileScreen.swift`**

Read the current file in full (post Plan 6b-1's Pro badge addition). Add, gated on `proEntitlementModel.isProEntitled`, a small theme picker (a `Picker` or row of swatches over `NCTheme.allCases`) and an alternate-icon picker, both calling `ThemeStore`'s methods. Construct `ThemeStore` as a `@State` here — unlike `AuthModel`/`ProEntitlementModel`, this one is genuinely fine as a per-screen instance since it's pure local `UserDefaults` state with no cross-screen synchronization need (there's no other screen that reads the current theme in this plan's scope) — but note this reasoning explicitly in a comment so a future plan extending theming elsewhere doesn't have to re-derive why this doesn't need environment injection.

- [ ] **Step 5: Add Localizable.xcstrings entries**

| Key | EN value |
|---|---|
| `theme.magentaDrift` | Magenta Drift |
| `theme.cyanPulse` | Cyan Pulse |
| `theme.sunsetOverdrive` | Sunset Overdrive |
| `profile.theme.title` | Theme |
| `profile.icon.title` | App Icon |

- [ ] **Step 6: Write the ops doc**

```markdown
# Alternate App Icons — asset & App Store Connect steps (manual)

Not expressible in code beyond the `project.yml`/`Info.plist` wiring (Plan
6b-2, Task 5). Spec §"Pro": "Icônes d'app... exclusifs."

## 1. Create the icon assets

Each alternate icon needs a full icon set (all required sizes) added to
`NeonCompass/Resources/Assets.xcassets` as a separate "App Icon" asset
(not the primary `AppIcon`). Original artwork only — no Rockstar/GTA
imagery, matching this project's hard IP constraint (CLAUDE.md).

## 2. Verify in TestFlight

Alternate icon switching (`UIApplication.setAlternateIconName`) only takes
visible effect on a real device/TestFlight build, not reliably in the
Simulator — verify the icon actually changes on the home screen with a
physical device before shipping.
```

- [ ] **Step 7: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Core/DesignSystem/NCTheme.swift NeonCompass/Features/Profile/ThemeStore.swift NeonCompass/Features/Profile/ProfileScreen.swift project.yml NeonCompass/Resources/Localizable.xcstrings docs/ops/2026-07-23-alternate-app-icons.md
git commit -m "feat: Pro exclusive themes + alternate app icon picker"
```

---

## Self-Review

**Spec coverage:**
- "Sync cloud de la progression iPhone↔iPad (nécessite le compte)" — Tasks 1-2. ✅
- "Planificateur d'itinéraire de collecte... tri glouton" — Task 3. ✅
- "Mode « reste à faire »" — Task 4. ✅
- "Icônes d'app et thèmes néon exclusifs + badge profil" — Task 5 (badge itself already shipped in Plan 6b-1). ✅
- Widgets, followed notifications — explicitly out of scope, Plan 6b-3.

**Known simplifications, disclosed not silently shipped:**
- Sync conflict resolution is pure last-write-wins-per-item on a client-supplied timestamp — no server-side clock authority, no handling of two devices racing within the same second, no merge UI. This is a deliberate simplification appropriate to this feature's actual stakes (a handful of boolean toggles, not collaborative editing) — a genuinely wrong resolution in the worst case means a user has to re-toggle one POI on one device, not data loss across the board (nothing is ever deleted server-side by this sync, only mirrored).
- The route planner UI is scoped as a numbered-list sheet, not a drawn polyline overlay on the map — the spec's wording ("planificateur... route optimisée") is satisfied by ordering; a visual polyline is a nice-to-have enhancement noted as optional in Task 3, not required.
- Task 5's alternate-icon asset creation is explicitly out of scope (no image-generation capability in this plan) — the code wiring is built assuming an asset that a human/designer must still create, tracked in the ops doc.
- Sync uploads are fire-and-forget with no retry/outbox mechanism, and `reconcile(with:)` is pull-only (it never re-pushes a local item whose `updatedAt` is newer than what's on the server). A toggle made while genuinely offline is not retried — it will only reach the other device if the user happens to re-toggle that same item again while online. This is an acceptable v1 gap given the "never block local functionality" constraint already governs this feature's design, but it means "sync" here is closer to "opportunistic mirroring" than a guaranteed-eventual-consistency system. A future hardening pass would need a local pending-upload queue with retry, and `reconcile` would need to also push (not just pull) whenever the local timestamp is newer.
