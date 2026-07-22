# Content Store Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three byte-for-byte-identical `ContentStore`/`CacheEntry`/`RemoteRepository` implementations (POI, Cheat, Guide) with one generic implementation, before a 4th content type (Plan 3d, "Actu") repeats the copy-paste a fourth time.

**Architecture:** Introduce a single generic `ContentStore<Item: Codable & Sendable>` backed by one shared SwiftData `@Model` (`ContentCacheEntry`, keyed by `collectionName` — the existing per-type cache entries already used this exact keying scheme, just duplicated per type) and a generic `FirestoreContentRepository<Item: Decodable & Sendable>` behind a primary-associated-type protocol (`ContentRemoteRepository<Item>`). Migrate POI, Cheat, and Guide onto it one at a time, deleting each old duplicate as its call site moves over, so the app compiles and its full test suite passes after every task.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, Swift Testing, Firebase Firestore/Remote Config (behind `Core/` protocols, unchanged).

## Global Constraints

- Swift 6 strict concurrency; no new Combine/TCA.
- Firebase stays behind `Core/` protocols — features never import Firebase directly (unchanged by this plan; `FirestoreContentRepository` is the only file that imports `FirebaseFirestore`, same as today's three `FirestoreXRepository` files).
- `#Predicate` must never capture `self` or a static member directly — always a locally captured `let` before the closure (existing convention, carried into the generic store).
- No behavior change: offline-first (cache loads synchronously on `init`), sync is strictly version-gated (`remoteVersion > localVersion`), Firestore decode is tolerant per-document (`compactMap` + `do/catch`, one bad document must never blank the whole collection). This plan is a pure refactor — every existing `ContentStoreTests`-style guarantee must still hold after migration.
- This is a pre-launch codebase (no shipped app, no user data) — no migration/compatibility shim is needed for the SwiftData schema change; old cache entries are simply dropped in favor of the new shared model.
- Every task must leave the app building and the full test suite (`Scripts/test.sh`) green — this is a refactor of infrastructure three features depend on; a broken intermediate state blocks everyone.

---

### Task 1: Generic core — `ContentCacheEntry`, `ContentRemoteRepository`, `ContentStore`, `FirestoreContentRepository`

**Files:**
- Create: `NeonCompass/Core/Content/ContentCacheEntry.swift`
- Create: `NeonCompass/Core/Content/ContentRemoteRepository.swift`
- Create: `NeonCompass/Core/Content/ContentStore.swift`
- Create: `NeonCompass/Core/Content/FirestoreContentRepository.swift`
- Modify: `NeonCompass/App/NeonCompassApp.swift:15` (add `ContentCacheEntry.self` to the model container list — additive only, the three old cache entry types stay registered until their migration task)
- Test: `NeonCompassTests/Content/ContentStoreTests.swift`
- Modify: `NeonCompassTests/Content/FakesTests.swift` (add a generic `FakeContentRepository<Item>`, additive — the existing `FakePOIRemoteRepository` and its test stay until Task 2)

**Interfaces:**
- Consumes: `POI` (`NeonCompass/Core/Map/POI.swift`) as the concrete `Item` used in this task's tests — already `Codable, Equatable, Identifiable, Sendable`. `ContentVersionProviding` and `FakeContentVersionProvider` (existing, unchanged).
- Produces: `ContentCacheEntry` (SwiftData `@Model`, `collectionName`/`json`/`version`), `ContentRemoteRepository<Item>` protocol (`func fetchAll() async throws -> [Item]`), `ContentStore<Item: Codable & Sendable>` (`init(collectionName:remote:versionProvider:modelContext:)`, `private(set) var items: [Item]`, `func syncIfNeeded() async throws`), `FirestoreContentRepository<Item: Decodable & Sendable>` (`init(collectionName:firestore:)`, conforms to `ContentRemoteRepository`). These four names are what every later task in this plan wires up — do not rename them mid-plan.

- [ ] **Step 1: Write the generic cache entry**

Create `NeonCompass/Core/Content/ContentCacheEntry.swift`:

```swift
import Foundation
import SwiftData

/// Cache SwiftData d'une collection de contenu entière, sérialisée en JSON.
/// Un seul type de modèle partagé entre tous les types de contenu
/// (POI, Cheat, Guide, ...), une ligne par `collectionName` — remplace les
/// trois `CacheEntry` dupliqués (POI/Cheat/Guide) qui ne différaient que
/// par leur nom de type.
/// v1 : granularité "toute la collection" (pas de delta par document) —
/// suffisant tant que le volume de contenu reste modeste (spec §7 : le
/// pipeline de contenu vise des dizaines à quelques centaines d'entrées).
@Model
final class ContentCacheEntry {
    @Attribute(.unique) var collectionName: String
    var json: Data
    var version: Int

    init(collectionName: String, json: Data, version: Int) {
        self.collectionName = collectionName
        self.json = json
        self.version = version
    }
}
```

- [ ] **Step 2: Write the generic remote repository protocol**

Create `NeonCompass/Core/Content/ContentRemoteRepository.swift`:

```swift
import Foundation

/// Abstraction sur la source distante d'un type de contenu (Firestore en
/// production). Remplace les trois protocoles dupliqués
/// (POIRemoteRepository/CheatRemoteRepository/GuideRemoteRepository).
protocol ContentRemoteRepository<Item>: Sendable {
    associatedtype Item: Sendable
    func fetchAll() async throws -> [Item]
}
```

- [ ] **Step 3: Write the generic content store**

Create `NeonCompass/Core/Content/ContentStore.swift`:

```swift
import Foundation
import Observation
import SwiftData

/// Store générique offline-first pour un type de contenu Firestore.
/// Remplace les trois implémentations dupliquées
/// (POIContentStore/CheatContentStore/GuideContentStore) — identiques à un
/// renommage de type près. `collectionName` est maintenant un paramètre
/// d'instance (au lieu d'une constante statique par type) puisqu'un seul
/// type générique sert toutes les collections.
@Observable
@MainActor
final class ContentStore<Item: Codable & Sendable> {
    private let collectionName: String
    private(set) var items: [Item]

    private let remote: any ContentRemoteRepository<Item>
    private let versionProvider: ContentVersionProviding
    private let modelContext: ModelContext

    init(
        collectionName: String,
        remote: any ContentRemoteRepository<Item>,
        versionProvider: ContentVersionProviding,
        modelContext: ModelContext
    ) {
        self.collectionName = collectionName
        self.remote = remote
        self.versionProvider = versionProvider
        self.modelContext = modelContext
        self.items = Self.loadCached(collectionName: collectionName, from: modelContext)
    }

    func syncIfNeeded() async throws {
        let remoteVersion = try await versionProvider.currentVersion()
        let localVersion = Self.cachedVersion(collectionName: collectionName, from: modelContext)
        guard remoteVersion > localVersion else { return }

        let fetched = try await remote.fetchAll()
        let data = try JSONEncoder().encode(fetched)

        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.json = data
            existing.version = remoteVersion
        } else {
            modelContext.insert(ContentCacheEntry(collectionName: name, json: data, version: remoteVersion))
        }
        try modelContext.save()

        items = fetched
    }

    private static func loadCached(collectionName: String, from modelContext: ModelContext) -> [Item] {
        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let decoded = try? JSONDecoder().decode([Item].self, from: entry.json) else {
            return []
        }
        return decoded
    }

    private static func cachedVersion(collectionName: String, from modelContext: ModelContext) -> Int {
        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        return (try? modelContext.fetch(descriptor).first?.version) ?? 0
    }
}
```

- [ ] **Step 4: Write the generic Firestore repository**

Create `NeonCompass/Core/Content/FirestoreContentRepository.swift`:

```swift
import FirebaseFirestore

/// Implémentation réelle de ContentRemoteRepository, adossée à Firestore.
/// Remplace les trois implémentations dupliquées
/// (FirestorePOIRepository/FirestoreCheatRepository/FirestoreGuideRepository).
/// Ne référence jamais FirebaseApp.configure() — la configuration de l'app
/// reste centralisée au niveau App, cette classe ne fait qu'utiliser
/// Firestore.firestore() une fois l'app configurée.
///
/// Décodage tolérant document-par-document : un document malformé ne doit
/// jamais vider toute la collection.
final class FirestoreContentRepository<Item: Decodable & Sendable>: ContentRemoteRepository {
    private let collection: CollectionReference
    private let typeName: String

    init(collectionName: String, firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection(collectionName)
        typeName = String(describing: Item.self)
    }

    func fetchAll() async throws -> [Item] {
        let snapshot = try await collection.getDocuments()
        return snapshot.documents.compactMap { document in
            do {
                let data = try JSONSerialization.data(withJSONObject: document.data())
                return try JSONDecoder().decode(Item.self, from: data)
            } catch {
                // A single malformed document (bad manual edit, future schema
                // drift) must not blank the entire collection — skip it and
                // keep the rest. Firestore-side validation at publish time
                // (content-cli's validate/check-publishable) is the primary
                // defense; this is defense-in-depth for whatever slips through.
                print("FirestoreContentRepository<\(typeName)>: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
```

- [ ] **Step 5: Add `ContentCacheEntry` to the app's model container (additive)**

In `NeonCompass/App/NeonCompassApp.swift:15`, change:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, POICacheEntry.self, CheatCacheEntry.self, FavoriteCheat.self, GuideCacheEntry.self])
```

to:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, POICacheEntry.self, CheatCacheEntry.self, FavoriteCheat.self, GuideCacheEntry.self, ContentCacheEntry.self])
```

(The three old cache entry types are removed one at a time in Tasks 2-4 as each migrates — this step only adds the new one so the schema is ready.)

- [ ] **Step 6: Add a generic fake repository for tests**

In `NeonCompassTests/Content/FakesTests.swift`, add this class alongside the existing `FakeContentVersionProvider` and `FakePOIRemoteRepository` (do not remove `FakePOIRemoteRepository` or its test yet — that happens in Task 2):

```swift
final class FakeContentRepository<Item: Sendable>: ContentRemoteRepository {
    nonisolated(unsafe) var itemsToReturn: [Item] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [Item] {
        fetchCallCount += 1
        return itemsToReturn
    }
}
```

- [ ] **Step 7: Write the failing tests for `ContentStore`**

Create `NeonCompassTests/Content/ContentStoreTests.swift`:

```swift
import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct ContentStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([ContentCacheEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func samplePOI(id: String) -> POI {
        POI(id: id, category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
            title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func startsEmptyWithNoCacheAndVersionZero() {
        let remote = FakeContentRepository<POI>()
        let version = FakeContentVersionProvider()
        let store = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: makeContext())
        #expect(store.items.isEmpty)
    }

    @Test func syncFetchesAndCachesWhenRemoteVersionIsNewer() async throws {
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let store = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: makeContext())

        try await store.syncIfNeeded()

        #expect(store.items.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func syncIsNoOpWhenVersionUnchanged() async throws {
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()
        let store = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        try await store.syncIfNeeded()

        let secondStore = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        try await secondStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)
    }

    @Test func loadsFromCacheOnInitWithoutNetworkCall() async throws {
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let firstStore = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        try await firstStore.syncIfNeeded()

        let secondStore = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        #expect(secondStore.items.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func differentCollectionNamesDoNotShareCache() async throws {
        let context = makeContext()
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1

        let poiStore = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        try await poiStore.syncIfNeeded()

        // Un store pour une autre collectionName ne doit jamais lire la ligne
        // ContentCacheEntry d'une autre collection — c'est le comportement
        // clé à préserver maintenant qu'un seul type de modèle sert toutes
        // les collections de contenu (avant : 3 types de modèle distincts,
        // l'isolation était structurelle plutôt que par clé).
        let otherStore = ContentStore<POI>(collectionName: "other", remote: remote, versionProvider: version, modelContext: context)
        #expect(otherStore.items.isEmpty)
    }
}
```

- [ ] **Step 8: Run the new tests to verify they pass**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including the 5 new `ContentStoreTests` tests. (Nothing depends on the generic store yet, so no existing test should change behavior.)

- [ ] **Step 9: Build the whole app to verify no regressions**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 10: Commit**

```bash
git add NeonCompass/Core/Content/ContentCacheEntry.swift NeonCompass/Core/Content/ContentRemoteRepository.swift NeonCompass/Core/Content/ContentStore.swift NeonCompass/Core/Content/FirestoreContentRepository.swift NeonCompass/App/NeonCompassApp.swift NeonCompassTests/Content/ContentStoreTests.swift NeonCompassTests/Content/FakesTests.swift
git commit -m "feat: add generic ContentStore/ContentCacheEntry/FirestoreContentRepository (consolidation, not yet wired to any feature)"
```

---

### Task 2: Migrate POI onto the generic store

**Files:**
- Modify: `NeonCompass/Features/Map/MapScreen.swift` (`loadModel()`)
- Modify: `NeonCompass/App/NeonCompassApp.swift:15` (remove `POICacheEntry.self`)
- Modify: `NeonCompassTests/Content/FakesTests.swift` (remove `FakePOIRemoteRepository` and its test — superseded by `ContentStoreTests` from Task 1)
- Delete: `NeonCompass/Core/Content/POIContentStore.swift`
- Delete: `NeonCompass/Core/Content/POICacheEntry.swift`
- Delete: `NeonCompass/Core/Content/POIRemoteRepository.swift`
- Delete: `NeonCompass/Core/Content/FirestorePOIRepository.swift`
- Delete: `NeonCompassTests/Content/POIContentStoreTests.swift`

**Interfaces:**
- Consumes: `ContentStore<Item>`, `FirestoreContentRepository<Item>` (Task 1). `MapModel(pois:modelContext:)` and `MapModel.updatePOIs(_:)` (existing, unchanged — only the caller's data source changes).
- Produces: nothing new — this task only removes the POI-specific duplication.

- [ ] **Step 1: Update `MapScreen.loadModel()` to use the generic store**

In `NeonCompass/Features/Map/MapScreen.swift`, replace the `loadModel()` method:

```swift
    private func loadModel() {
        guard model == nil else { return }
        guard FirebaseAvailability.isConfigured else {
            // Firebase not yet activated (Task 7 of Plan 3) — load with no
            // remote content rather than crashing. The map still works with
            // zero POIs; personal pins and "found" tracking are unaffected
            // since those go through FoundEntry/PersonalPin, not this path.
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
        Task {
            try? await contentStore.syncIfNeeded()
            model?.updatePOIs(contentStore.items)
        }
    }
```

- [ ] **Step 2: Remove `POICacheEntry` from the model container**

In `NeonCompass/App/NeonCompassApp.swift:15`, change:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, POICacheEntry.self, CheatCacheEntry.self, FavoriteCheat.self, GuideCacheEntry.self, ContentCacheEntry.self])
```

to:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, CheatCacheEntry.self, FavoriteCheat.self, GuideCacheEntry.self, ContentCacheEntry.self])
```

- [ ] **Step 3: Delete the now-unused POI-specific infrastructure**

```bash
git rm NeonCompass/Core/Content/POIContentStore.swift NeonCompass/Core/Content/POICacheEntry.swift NeonCompass/Core/Content/POIRemoteRepository.swift NeonCompass/Core/Content/FirestorePOIRepository.swift NeonCompassTests/Content/POIContentStoreTests.swift
```

- [ ] **Step 4: Remove `FakePOIRemoteRepository` and its test from `FakesTests.swift`**

In `NeonCompassTests/Content/FakesTests.swift`, remove the `FakePOIRemoteRepository` class and the `remoteRepositoryTracksFetchCallsAndReturnsSetPOIs` test — `ContentStoreTests` (Task 1) already covers `ContentStore<POI>` fetch/cache behavior generically via `FakeContentRepository<POI>`. Keep `FakeContentVersionProvider`, its test, and `FakeContentRepository`. The file should read:

```swift
import Testing
@testable import NeonCompass

final class FakeContentVersionProvider: ContentVersionProviding {
    nonisolated(unsafe) var version: Int = 0
    func currentVersion() async throws -> Int { version }
}

final class FakeContentRepository<Item: Sendable>: ContentRemoteRepository {
    nonisolated(unsafe) var itemsToReturn: [Item] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [Item] {
        fetchCallCount += 1
        return itemsToReturn
    }
}

struct FakesTests {
    @Test func versionProviderReturnsSetValue() async throws {
        let fake = FakeContentVersionProvider()
        fake.version = 5
        #expect(try await fake.currentVersion() == 5)
    }
}
```

- [ ] **Step 5: Run the full test suite**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **` — `MapModelTests` (unchanged, exercises `MapModel` directly) and `ContentStoreTests` (Task 1) together cover what `POIContentStoreTests` used to cover.

- [ ] **Step 6: Build the app**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Features/Map/MapScreen.swift NeonCompass/App/NeonCompassApp.swift NeonCompassTests/Content/FakesTests.swift
git rm NeonCompass/Core/Content/POIContentStore.swift NeonCompass/Core/Content/POICacheEntry.swift NeonCompass/Core/Content/POIRemoteRepository.swift NeonCompass/Core/Content/FirestorePOIRepository.swift NeonCompassTests/Content/POIContentStoreTests.swift
git commit -m "refactor: migrate POI content sync onto the generic ContentStore"
```

---

### Task 3: Migrate Cheat onto the generic store

**Files:**
- Modify: `NeonCompass/Features/Cheats/CheatsScreen.swift` (`loadCheatsModel()`)
- Modify: `NeonCompass/App/NeonCompassApp.swift:15` (remove `CheatCacheEntry.self`)
- Delete: `NeonCompass/Core/Content/CheatContentStore.swift`
- Delete: `NeonCompass/Core/Content/CheatCacheEntry.swift`
- Delete: `NeonCompass/Core/Content/CheatRemoteRepository.swift`
- Delete: `NeonCompass/Core/Content/FirestoreCheatRepository.swift`
- Delete: `NeonCompassTests/Content/CheatContentStoreTests.swift`

**Interfaces:**
- Consumes: `ContentStore<Item>`, `FirestoreContentRepository<Item>` (Task 1). `CheatsModel(cheats:modelContext:)` and `CheatsModel.updateCheats(_:)` (existing, unchanged).
- Produces: nothing new — this task only removes the Cheat-specific duplication.

- [ ] **Step 1: Update `CheatsScreen.loadCheatsModel()` to use the generic store**

In `NeonCompass/Features/Cheats/CheatsScreen.swift`, replace the `loadCheatsModel()` method:

```swift
    private func loadCheatsModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<Cheat>(
            collectionName: "cheats",
            remote: FirestoreContentRepository<Cheat>(collectionName: "cheats"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = CheatsModel(cheats: contentStore.items, modelContext: modelContext)
        try? await contentStore.syncIfNeeded()
        model?.updateCheats(contentStore.items)
    }
```

- [ ] **Step 2: Remove `CheatCacheEntry` from the model container**

In `NeonCompass/App/NeonCompassApp.swift:15`, change:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, CheatCacheEntry.self, FavoriteCheat.self, GuideCacheEntry.self, ContentCacheEntry.self])
```

to:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, GuideCacheEntry.self, ContentCacheEntry.self])
```

- [ ] **Step 3: Delete the now-unused Cheat-specific infrastructure**

```bash
git rm NeonCompass/Core/Content/CheatContentStore.swift NeonCompass/Core/Content/CheatCacheEntry.swift NeonCompass/Core/Content/CheatRemoteRepository.swift NeonCompass/Core/Content/FirestoreCheatRepository.swift NeonCompassTests/Content/CheatContentStoreTests.swift
```

(`CheatContentStoreTests.swift` defines `FakeCheatRemoteRepository` inline — it is deleted with the file, and nothing else references that fake.)

- [ ] **Step 4: Run the full test suite**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **` — `CheatsModelTests` (unchanged) and `ContentStoreTests` (Task 1) together cover what `CheatContentStoreTests` used to cover.

- [ ] **Step 5: Build the app**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatsScreen.swift NeonCompass/App/NeonCompassApp.swift
git rm NeonCompass/Core/Content/CheatContentStore.swift NeonCompass/Core/Content/CheatCacheEntry.swift NeonCompass/Core/Content/CheatRemoteRepository.swift NeonCompass/Core/Content/FirestoreCheatRepository.swift NeonCompassTests/Content/CheatContentStoreTests.swift
git commit -m "refactor: migrate Cheat content sync onto the generic ContentStore"
```

---

### Task 4: Migrate Guide onto the generic store

**Files:**
- Modify: `NeonCompass/Features/Cheats/CheatsScreen.swift` (`loadGuidesModel()`)
- Modify: `NeonCompass/App/NeonCompassApp.swift:15` (remove `GuideCacheEntry.self` — this is the last of the three old cache entry types, container ends at 4 model types)
- Delete: `NeonCompass/Core/Content/GuideContentStore.swift`
- Delete: `NeonCompass/Core/Content/GuideCacheEntry.swift`
- Delete: `NeonCompass/Core/Content/GuideRemoteRepository.swift`
- Delete: `NeonCompass/Core/Content/FirestoreGuideRepository.swift`
- Delete: `NeonCompassTests/Content/GuideContentStoreTests.swift`

**Interfaces:**
- Consumes: `ContentStore<Item>`, `FirestoreContentRepository<Item>` (Task 1). `GuidesModel(guides:)` and `GuidesModel.updateGuides(_:)` (existing, unchanged).
- Produces: nothing new — this is the final migration. After this task, `ContentCacheEntry` is the only content cache model in the app.

- [ ] **Step 1: Update `CheatsScreen.loadGuidesModel()` to use the generic store**

In `NeonCompass/Features/Cheats/CheatsScreen.swift`, replace the `loadGuidesModel()` method:

```swift
    private func loadGuidesModel() async {
        guard guidesModel == nil else { return }
        let contentStore = ContentStore<Guide>(
            collectionName: "guides",
            remote: FirestoreContentRepository<Guide>(collectionName: "guides"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        guidesModel = GuidesModel(guides: contentStore.items)
        try? await contentStore.syncIfNeeded()
        guidesModel?.updateGuides(contentStore.items)
    }
```

- [ ] **Step 2: Remove `GuideCacheEntry` from the model container**

In `NeonCompass/App/NeonCompassApp.swift:15`, change:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, GuideCacheEntry.self, ContentCacheEntry.self])
```

to:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self])
```

- [ ] **Step 3: Delete the now-unused Guide-specific infrastructure**

```bash
git rm NeonCompass/Core/Content/GuideContentStore.swift NeonCompass/Core/Content/GuideCacheEntry.swift NeonCompass/Core/Content/GuideRemoteRepository.swift NeonCompass/Core/Content/FirestoreGuideRepository.swift NeonCompassTests/Content/GuideContentStoreTests.swift
```

- [ ] **Step 4: Run the full test suite**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **` — `GuidesModelTests` (unchanged) and `ContentStoreTests` (Task 1) together cover what `GuideContentStoreTests` used to cover. Total test count will be lower than before this plan (three redundant per-type `ContentStore` test files removed) — that is expected, not a coverage regression: the generic behavior they tested is now tested once in `ContentStoreTests`.

- [ ] **Step 5: Build the app**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Verify no other references to the deleted types remain**

Run: `grep -rn "POIContentStore\|CheatContentStore\|GuideContentStore\|POICacheEntry\|CheatCacheEntry\|GuideCacheEntry\|POIRemoteRepository\|CheatRemoteRepository\|GuideRemoteRepository\|FirestorePOIRepository\|FirestoreCheatRepository\|FirestoreGuideRepository" NeonCompass NeonCompassTests`
Expected: no output (empty). If anything is found, it is a leftover reference this plan missed — fix it before committing.

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatsScreen.swift NeonCompass/App/NeonCompassApp.swift
git rm NeonCompass/Core/Content/GuideContentStore.swift NeonCompass/Core/Content/GuideCacheEntry.swift NeonCompass/Core/Content/GuideRemoteRepository.swift NeonCompass/Core/Content/FirestoreGuideRepository.swift NeonCompassTests/Content/GuideContentStoreTests.swift
git commit -m "refactor: migrate Guide content sync onto the generic ContentStore (consolidation complete)"
```

---

## Self-Review

**Couverture spec** : ce plan est un refactor pur, sans surface produit nouvelle — aucun jalon spec ne le couvre directement. Il exécute la dette explicitement flaggée dans le self-review du Plan 3c ("consolider avant qu'un 4e type de contenu n'apparaisse") avant que le Plan 3d (Actu) n'ajoute ce 4e type.

**Cohérence des types** : `ContentStore<Item>`, `ContentRemoteRepository<Item>`, `FirestoreContentRepository<Item>`, `ContentCacheEntry` sont définis une fois (Task 1) et réutilisés à l'identique dans les Tasks 2-4 — aucun renommage en cours de route.

**Non-régression** : chaque tâche de migration (2, 3, 4) laisse l'app buildable et la suite de tests complète verte avant de committer — le comportement offline-first, le version-gating, et le décodage tolérant document-par-document sont préservés à l'identique (vérifiés une fois génériquement dans `ContentStoreTests`, Task 1, plutôt que trois fois).

**Ordre des tâches** : Task 1 (infra générique, additive, ne casse rien) doit précéder les Tasks 2-4 (migrations, une par type de contenu). Les Tasks 2-4 sont indépendantes entre elles une fois Task 1 posée — un exécuteur pourrait les paralléliser, mais ce plan les ordonne POI → Cheat → Guide par simplicité de revue (le rouleau "un onglet, deux sections" de CheatsScreen.swift signifie que Task 3 et Task 4 touchent le même fichier ; les garder séquentielles évite un conflit de merge inutile).

**Dette non traitée par ce plan (rappel, pas nouveau)** :
1. **Toggle favoris/found non-réactif** (`MapModel`/`CheatsModel`) — toujours hors scope, reporté au Plan 4 (Progression).
2. **Migration français-primaire** — toujours documentée seulement (CLAUDE.md), non appliquée.

**Prochaine étape après ce plan** : Plan 3d (Actu/feed) peut être écrit et exécuté en construisant directement sur `ContentStore<NewsItem>` / `FirestoreContentRepository<NewsItem>` — pas de 4e duplication.
