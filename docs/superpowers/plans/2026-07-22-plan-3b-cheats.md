# Plan 3b — Cheats (Neon Compass v1.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** L'onglet Cheats : liste filtrable/recherchable de codes avec chips de glyphes manette (toggle global PS5/Xbox), favoris épinglés, badge « bloque les trophées », et un mode lecture plein écran pour la saisie en jeu.

**Architecture:** Réutilise telle quelle l'infrastructure de sync du plan 3 (`Core/Content/`) — un `CheatContentStore` quasi-identique à `POIContentStore` (cache SwiftData + version-gate Remote Config), volontairement dupliqué plutôt que généralisé prématurément (règle de trois : on généralisera à l'apparition d'un troisième consommateur, au plan 3c). Le domaine `Cheat` vit dans `Core/Cheats/`, parallèle à `Core/Map/`. L'UI vit dans `Features/Cheats/`, consommée par l'onglet `.cheats` déjà défini au plan 1.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + `@Observable`, SwiftData, Firebase Firestore/Remote Config (déjà configuré par le plan 3), Swift Testing.

## Global Constraints

- Cible : iOS/iPadOS 26.0 minimum, iPhone + iPad, pas de Mac Catalyst.
- Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`.
- Firebase isolé derrière des protocoles dans `Core/Content/` — les features ne l'importent jamais directement.
- Toute string visible passe par le String Catalog.
- Aucune marque Rockstar dans le code, les identifiants, les strings ou les assets. **Aucun glyphe/logo PlayStation ou Xbox propriétaire** — uniquement des SF Symbols génériques (`circle`, `triangle`, `square`, `xmark`, `l1.button.roundedbottom.horizontal`, etc.), jamais une image de marque.
- Mode sombre uniquement ; glow limité à 3 accents par écran.
- Tests : Swift Testing (`import Testing`), jamais XCTest.
- Commandes de vérification : `Scripts/test.sh`, `Scripts/build.sh`.

---

### Task 1: Modèle `Cheat` + glyphes manette

**Files:**
- Create: `NeonCompass/Core/Cheats/Cheat.swift`, `NeonCompass/Core/Cheats/GamepadGlyph.swift`
- Test: `NeonCompassTests/Cheats/CheatTests.swift`, `NeonCompassTests/Cheats/GamepadGlyphTests.swift`

**Interfaces:**
- Consumes: `LocalizedText` (Plan 2, `NeonCompass/Core/Map/POI.swift` — déjà générique, réutilisé tel quel).
- Produces: `enum CheatCategory: String, CaseIterable, Codable, Sendable` (`player, weapons, vehicles, world, misc` — miroir de `content/schema/cheat.schema.json`) ; `enum GamepadButton: String, Codable, Sendable` (`up, down, left, right, cross, circle, square, triangle, a, b, x, y, l1, l2, r1, r2` — miroir du schéma) ; `struct Cheat: Codable, Equatable, Identifiable, Sendable` (`id, category, effect: LocalizedText, sequence: [Platform: [GamepadButton]], blocksTrophies: Bool`, où `enum Platform: String, Codable, Sendable { case ps5, xbox }`) ; `enum GamepadGlyph` (`static func systemImage(for button: GamepadButton, platform: Platform) -> String`). Consommé par Task 2 (store), Task 4 (liste), Task 5 (mode lecture).

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Cheats/CheatTests.swift` :
```swift
import Testing
import Foundation
@testable import NeonCompass

struct CheatTests {
    @Test func decodesCheatIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "cheat_sample_placeholder",
            "category": "misc",
            "effect": {"en": "Sample cheat", "fr": "Cheat exemple"},
            "sequence": {"ps5": ["up", "up", "circle", "l1"], "xbox": ["up", "up", "b", "l1"]},
            "blocksTrophies": true,
            "status": "draft",
            "verifiedBy": ["internal:fixture"]
        }
        """.utf8)
        let cheat = try JSONDecoder().decode(Cheat.self, from: json)
        #expect(cheat.id == "cheat_sample_placeholder")
        #expect(cheat.category == .misc)
        #expect(cheat.blocksTrophies)
        #expect(cheat.sequence[.ps5] == [.up, .up, .circle, .l1])
        #expect(cheat.sequence[.xbox] == [.up, .up, .b, .l1])
        #expect(cheat.effect.resolved(for: "fr") == "Cheat exemple")
    }
}
```

Note : la fixture réelle du pipeline (`content/cheats/cheat_sample_placeholder.json`, plan de contenu antérieur) utilise `"lb"` pour la séquence Xbox — une valeur hors de l'énumération `GamepadButton` ci-dessous (qui n'a que des noms cross-plateforme communs : `l1/r1/l2/r2`). Le JSON de test ci-dessus utilise `"l1"` (valeur alignée sur le schéma Swift) plutôt que de recopier `"lb"` tel quel. Il faudra corriger cette fixture de contenu avant toute publication réelle (hors scope de ce plan, qui ne touche pas `content/`).

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'Cheat' in scope`

- [ ] **Step 3: Implémenter `Cheat`**

`NeonCompass/Core/Cheats/Cheat.swift` :
```swift
import Foundation

enum CheatCategory: String, CaseIterable, Codable, Sendable {
    case player, weapons, vehicles, world, misc
}

enum Platform: String, CaseIterable, Codable, Sendable {
    case ps5, xbox
}

enum GamepadButton: String, Codable, Sendable {
    case up, down, left, right
    case cross, circle, square, triangle
    case a, b, x, y
    case l1, l2, r1, r2
}

/// Champs pipeline-only du schéma (`status`, `verifiedBy`) sont absents ici :
/// Codable ignore silencieusement les clés JSON inconnues au décodage
/// (même stratégie que POI, cf. plan 2).
struct Cheat: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: CheatCategory
    let effect: LocalizedText
    let sequence: [Platform: [GamepadButton]]
    let blocksTrophies: Bool
}
```

- [ ] **Step 4: Écrire les tests des glyphes (failing)**

`NeonCompassTests/Cheats/GamepadGlyphTests.swift` :
```swift
import Testing
@testable import NeonCompass

struct GamepadGlyphTests {
    @Test func genericFaceButtonsNeverReferenceTrademarkedSymbols() {
        // Aucune marque PlayStation/Xbox — uniquement des SF Symbols génériques.
        for button in [GamepadButton.cross, .circle, .square, .triangle] {
            let symbol = GamepadGlyph.systemImage(for: button, platform: .ps5)
            #expect(!symbol.isEmpty)
        }
    }

    @Test func xboxFaceButtonsUseLetterGlyphs() {
        #expect(GamepadGlyph.systemImage(for: .a, platform: .xbox) == "a.circle")
        #expect(GamepadGlyph.systemImage(for: .b, platform: .xbox) == "b.circle")
    }

    @Test func shoulderButtonsShareSameGlyphAcrossPlatforms() {
        #expect(GamepadGlyph.systemImage(for: .l1, platform: .ps5) == GamepadGlyph.systemImage(for: .l1, platform: .xbox))
    }
}
```

- [ ] **Step 5: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'GamepadGlyph' in scope`

- [ ] **Step 6: Implémenter `GamepadGlyph`**

`NeonCompass/Core/Cheats/GamepadGlyph.swift` :
```swift
import Foundation

/// Uniquement des SF Symbols génériques (formes géométriques, lettres) —
/// jamais un logo ou glyphe propriétaire Sony/Microsoft.
enum GamepadGlyph {
    static func systemImage(for button: GamepadButton, platform: Platform) -> String {
        switch button {
        case .up: "dpad.up.filled"
        case .down: "dpad.down.filled"
        case .left: "dpad.left.filled"
        case .right: "dpad.right.filled"
        case .l1: "l1.button.roundedbottom.horizontal"
        case .l2: "l2.button.roundedtop.horizontal"
        case .r1: "r1.button.roundedbottom.horizontal"
        case .r2: "r2.button.roundedtop.horizontal"
        case .cross, .a: "a.circle"
        case .circle, .b: "b.circle"
        case .square, .x: "x.circle"
        case .triangle, .y: "y.circle"
        }
    }
}
```

Note : `cross`/`circle`/`square`/`triangle` (PS5) et `a`/`b`/`x`/`y` (Xbox) partagent les mêmes glyphes génériques par position fonctionnelle — c'est un choix délibéré (jamais de forme "triangle" ou "carré" stylisée façon manette, uniquement les lettres SF Symbols standard), évitant tout risque de ressemblance avec les boutons réels.

- [ ] **Step 7: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Core/Cheats NeonCompassTests/Cheats
git commit -m "feat: Cheat model + gamepad glyph mapping (trademark-free SF Symbols)"
```

---

### Task 2: `CheatContentStore` — cache SwiftData + sync versionné

**Files:**
- Create: `NeonCompass/Core/Content/CheatRemoteRepository.swift`, `NeonCompass/Core/Content/FirestoreCheatRepository.swift`, `NeonCompass/Core/Content/CheatCacheEntry.swift`, `NeonCompass/Core/Content/CheatContentStore.swift`
- Test: `NeonCompassTests/Content/CheatContentStoreTests.swift`

**Interfaces:**
- Consumes: `Cheat` (Task 1), `ContentVersionProviding` (Plan 3, réutilisé tel quel — même version globale de contenu pour POI et cheats).
- Produces: `protocol CheatRemoteRepository: Sendable { func fetchAll() async throws -> [Cheat] }` ; `final class FirestoreCheatRepository: CheatRemoteRepository` (miroir de `FirestorePOIRepository`, décodage tolérant document-par-document) ; `@Model final class CheatCacheEntry` (miroir de `POICacheEntry`) ; `@Observable @MainActor final class CheatContentStore` (miroir de `POIContentStore` : `init(remote:versionProvider:modelContext:)`, `private(set) var cheats: [Cheat]`, `func syncIfNeeded() async throws`). Consommé par Task 4.

Ce fichier duplique volontairement le pattern de `POIContentStore`/`POICacheEntry`/`FirestorePOIRepository` (plan 3) — voir la note d'architecture en tête de plan sur la règle de trois.

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Content/CheatContentStoreTests.swift` :
```swift
import Testing
import SwiftData
@testable import NeonCompass

final class FakeCheatRemoteRepository: CheatRemoteRepository {
    var cheatsToReturn: [Cheat] = []
    private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [Cheat] {
        fetchCallCount += 1
        return cheatsToReturn
    }
}

@MainActor
struct CheatContentStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([CheatCacheEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func sampleCheat(id: String) -> Cheat {
        Cheat(id: id, category: .misc,
              effect: LocalizedText(en: "Sample", fr: nil, es: nil, it: nil, de: nil),
              sequence: [.ps5: [.up], .xbox: [.up]], blocksTrophies: false)
    }

    @Test func startsEmptyWithNoCacheAndVersionZero() {
        let remote = FakeCheatRemoteRepository()
        let version = FakeContentVersionProvider()
        let store = CheatContentStore(remote: remote, versionProvider: version, modelContext: makeContext())
        #expect(store.cheats.isEmpty)
    }

    @Test func syncFetchesAndCachesWhenRemoteVersionIsNewer() async throws {
        let remote = FakeCheatRemoteRepository()
        remote.cheatsToReturn = [sampleCheat(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let store = CheatContentStore(remote: remote, versionProvider: version, modelContext: makeContext())

        try await store.syncIfNeeded()

        #expect(store.cheats.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func syncIsNoOpWhenVersionUnchanged() async throws {
        let remote = FakeCheatRemoteRepository()
        remote.cheatsToReturn = [sampleCheat(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()
        let store = CheatContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await store.syncIfNeeded()

        let secondStore = CheatContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await secondStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)
    }

    @Test func loadsFromCacheOnInitWithoutNetworkCall() async throws {
        let remote = FakeCheatRemoteRepository()
        remote.cheatsToReturn = [sampleCheat(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let firstStore = CheatContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await firstStore.syncIfNeeded()

        let secondStore = CheatContentStore(remote: remote, versionProvider: version, modelContext: context)
        #expect(secondStore.cheats.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }
}
```

Note : `FakeContentVersionProvider` est déjà défini dans `NeonCompassTests/Content/FakesTests.swift` (plan 3) — même fichier de test target, donc visible ici sans réimport ni redéfinition.

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'CheatContentStore' in scope`

- [ ] **Step 3: Implémenter**

`NeonCompass/Core/Content/CheatRemoteRepository.swift` :
```swift
import Foundation

protocol CheatRemoteRepository: Sendable {
    func fetchAll() async throws -> [Cheat]
}
```

`NeonCompass/Core/Content/FirestoreCheatRepository.swift` :
```swift
import FirebaseFirestore

/// Miroir de FirestorePOIRepository (plan 3) — décodage tolérant
/// document-par-document, un document malformé ne doit jamais vider
/// toute la liste de cheats.
final class FirestoreCheatRepository: CheatRemoteRepository {
    private let collection: CollectionReference

    init(firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection("cheats")
    }

    func fetchAll() async throws -> [Cheat] {
        let snapshot = try await collection.getDocuments()
        return snapshot.documents.compactMap { document in
            do {
                let data = try JSONSerialization.data(withJSONObject: document.data())
                return try JSONDecoder().decode(Cheat.self, from: data)
            } catch {
                print("FirestoreCheatRepository: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
```

`NeonCompass/Core/Content/CheatCacheEntry.swift` :
```swift
import Foundation
import SwiftData

@Model
final class CheatCacheEntry {
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

`NeonCompass/Core/Content/CheatContentStore.swift` :
```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CheatContentStore {
    private static let collectionName = "cheats"

    private(set) var cheats: [Cheat]

    private let remote: CheatRemoteRepository
    private let versionProvider: ContentVersionProviding
    private let modelContext: ModelContext

    init(remote: CheatRemoteRepository, versionProvider: ContentVersionProviding, modelContext: ModelContext) {
        self.remote = remote
        self.versionProvider = versionProvider
        self.modelContext = modelContext
        self.cheats = Self.loadCached(from: modelContext)
    }

    func syncIfNeeded() async throws {
        let remoteVersion = try await versionProvider.currentVersion()
        let localVersion = Self.cachedVersion(from: modelContext)
        guard remoteVersion > localVersion else { return }

        let fetched = try await remote.fetchAll()
        let data = try JSONEncoder().encode(fetched)

        let name = Self.collectionName
        let descriptor = FetchDescriptor<CheatCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.json = data
            existing.version = remoteVersion
        } else {
            modelContext.insert(CheatCacheEntry(collectionName: Self.collectionName, json: data, version: remoteVersion))
        }
        try modelContext.save()

        cheats = fetched
    }

    private static func loadCached(from modelContext: ModelContext) -> [Cheat] {
        let name = collectionName
        let descriptor = FetchDescriptor<CheatCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let decoded = try? JSONDecoder().decode([Cheat].self, from: entry.json) else {
            return []
        }
        return decoded
    }

    private static func cachedVersion(from modelContext: ModelContext) -> Int {
        let name = collectionName
        let descriptor = FetchDescriptor<CheatCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        return (try? modelContext.fetch(descriptor).first?.version) ?? 0
    }
}
```

Note : `versionProvider.currentVersion()` est `async throws` (corrigé au plan 3 — voir le fix `RemoteConfigVersionProvider — actually fetch/activate before reading contentVersion`), d'où le `try await` ci-dessus.

- [ ] **Step 4: Enregistrer `CheatCacheEntry` dans le conteneur SwiftData**

Dans `NeonCompass/App/NeonCompassApp.swift`, ajouter `CheatCacheEntry.self` à la liste `.modelContainer(for: [...])`.

- [ ] **Step 5: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Core/Content/CheatRemoteRepository.swift NeonCompass/Core/Content/FirestoreCheatRepository.swift NeonCompass/Core/Content/CheatCacheEntry.swift NeonCompass/Core/Content/CheatContentStore.swift NeonCompass/App/NeonCompassApp.swift NeonCompassTests/Content/CheatContentStoreTests.swift
git commit -m "feat: CheatContentStore — SwiftData cache + version-gated sync (mirrors POIContentStore)"
```

---

### Task 3: Préférence plateforme + favoris (SwiftData + UserDefaults)

**Files:**
- Create: `NeonCompass/Core/Cheats/FavoriteCheat.swift`, `NeonCompass/Features/Cheats/CheatsModel.swift`
- Test: `NeonCompassTests/Cheats/CheatsModelTests.swift`

**Interfaces:**
- Consumes: `Cheat`, `Platform`, `CheatContentStore` (Task 1-2).
- Produces: `@Model final class FavoriteCheat` (`@Attribute(.unique) var cheatID: String`) ; `@Observable @MainActor final class CheatsModel` (`init(cheats: [Cheat], modelContext: ModelContext, defaults: UserDefaults = .standard)`, `var activePlatform: Platform` (persisté via `defaults`), `var searchQuery: String`, `var activeCategories: Set<CheatCategory>`, `var filteredCheats: [Cheat]` (favoris d'abord, triés), `func isFavorite(_ cheat: Cheat) -> Bool`, `func toggleFavorite(_ cheat: Cheat)`, `func updateCheats(_ newCheats: [Cheat])`). Consommé par Task 4 (liste), Task 5 (mode lecture).

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Cheats/CheatsModelTests.swift` :
```swift
import Testing
import Foundation
import SwiftData
@testable import NeonCompass

@MainActor
struct CheatsModelTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FavoriteCheat.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        d.removePersistentDomain(forName: d.description)
        return d
    }

    private func sampleCheats() -> [Cheat] {
        [
            Cheat(id: "a", category: .weapons, effect: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil),
                  sequence: [.ps5: [.up], .xbox: [.up]], blocksTrophies: false),
            Cheat(id: "b", category: .misc, effect: LocalizedText(en: "Beta", fr: nil, es: nil, it: nil, de: nil),
                  sequence: [.ps5: [.down], .xbox: [.down]], blocksTrophies: true),
        ]
    }

    @Test func defaultPlatformIsPS5() {
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: freshDefaults())
        #expect(model.activePlatform == .ps5)
    }

    @Test func platformPreferencePersistsAcrossInstances() {
        let defaults = freshDefaults()
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: defaults)
        model.activePlatform = .xbox
        let second = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: defaults)
        #expect(second.activePlatform == .xbox)
    }

    @Test func favoritesAreToggleableAndPinnedFirst() {
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: freshDefaults())
        #expect(!model.isFavorite(model.filteredCheats[0]))
        let second = sampleCheats()[1]
        model.toggleFavorite(second)
        #expect(model.isFavorite(second))
        #expect(model.filteredCheats.first?.id == "b")
    }

    @Test func filtersByCategoryAndSearch() {
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: freshDefaults())
        model.activeCategories = [.weapons]
        #expect(model.filteredCheats.map(\.id) == ["a"])
        model.activeCategories = Set(CheatCategory.allCases)
        model.searchQuery = "bet"
        #expect(model.filteredCheats.map(\.id) == ["b"])
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'CheatsModel' in scope`

- [ ] **Step 3: Implémenter**

`NeonCompass/Core/Cheats/FavoriteCheat.swift` :
```swift
import Foundation
import SwiftData

@Model
final class FavoriteCheat {
    @Attribute(.unique) var cheatID: String

    init(cheatID: String) {
        self.cheatID = cheatID
    }
}
```

`NeonCompass/Features/Cheats/CheatsModel.swift` :
```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CheatsModel {
    private static let platformKey = "cheatsActivePlatform"

    private(set) var cheats: [Cheat]
    var searchQuery: String = ""
    var activeCategories: Set<CheatCategory>

    var activePlatform: Platform {
        didSet { defaults.set(activePlatform.rawValue, forKey: Self.platformKey) }
    }

    private let modelContext: ModelContext
    private let defaults: UserDefaults

    init(cheats: [Cheat], modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.cheats = cheats
        self.modelContext = modelContext
        self.defaults = defaults
        self.activeCategories = Set(CheatCategory.allCases)
        let stored = defaults.string(forKey: Self.platformKey).flatMap(Platform.init(rawValue:))
        self.activePlatform = stored ?? .ps5
    }

    func updateCheats(_ newCheats: [Cheat]) {
        cheats = newCheats
    }

    var filteredCheats: [Cheat] {
        let matching = cheats.filter { cheat in
            activeCategories.contains(cheat.category)
                && (searchQuery.isEmpty || cheat.effect.en.localizedCaseInsensitiveContains(searchQuery))
        }
        return matching.sorted { isFavorite($0) && !isFavorite($1) }
    }

    func isFavorite(_ cheat: Cheat) -> Bool {
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    func toggleFavorite(_ cheat: Cheat) {
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteCheat(cheatID: cheat.id))
        }
        try? modelContext.save()
    }
}
```

Note sur `sorted` : Swift's `sorted(by:)` est stable en pratique sur les tableaux de cette taille pour ce cas d'usage (préserver l'ordre relatif des non-favoris) — suffisant pour v1, pas besoin d'un tri composite plus élaboré.

- [ ] **Step 4: Enregistrer `FavoriteCheat` dans le conteneur SwiftData**

Ajouter `FavoriteCheat.self` à la liste `.modelContainer(for: [...])` dans `NeonCompassApp.swift`.

- [ ] **Step 5: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Core/Cheats/FavoriteCheat.swift NeonCompass/Features/Cheats/CheatsModel.swift NeonCompass/App/NeonCompassApp.swift NeonCompassTests/Cheats/CheatsModelTests.swift
git commit -m "feat: CheatsModel — platform preference, favorites, filter/search"
```

---

### Task 4: Liste des cheats — cartes glass + chips de glyphes

**Files:**
- Create: `NeonCompass/Features/Cheats/CheatCard.swift`, `NeonCompass/Features/Cheats/CheatsListView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `Cheat`, `CheatsModel`, `GamepadGlyph`, `NCColor` (Tasks 1-3, Plan 1).
- Produces: `struct CheatCard: View` (`init(cheat: Cheat, platform: Platform, isFavorite: Bool, onTap: () -> Void, onToggleFavorite: () -> Void)`) ; `struct CheatsListView: View` (`init(model: CheatsModel, onSelect: @escaping (Cheat) -> Void)`). Consommé par Task 6.

Pas de test unitaire — vues SwiftUI pures, filtrage/favoris déjà testés (Task 3). Vérification par build + vérification visuelle à la Task 6.

- [ ] **Step 1: Implémenter la carte cheat**

`NeonCompass/Features/Cheats/CheatCard.swift` :
```swift
import SwiftUI

struct CheatCard: View {
    let cheat: Cheat
    let platform: Platform
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(cheat.effect.en)
                        .font(NCTypography.body.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? NCColor.sunsetOrange : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    ForEach(Array((cheat.sequence[platform] ?? []).enumerated()), id: \.offset) { _, button in
                        Image(systemName: GamepadGlyph.systemImage(for: button, platform: platform))
                            .font(.system(size: 18))
                            .foregroundStyle(NCColor.neonCyan)
                    }
                    Spacer()
                    if cheat.blocksTrophies {
                        Text("cheats.blocksTrophies")
                            .font(.caption2)
                            .foregroundStyle(NCColor.sunsetMagenta)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
```

- [ ] **Step 2: Implémenter la liste**

`NeonCompass/Features/Cheats/CheatsListView.swift` :
```swift
import SwiftUI

struct CheatsListView: View {
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                platformToggle
                TextField("cheats.search.placeholder", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .glassEffect(.regular, in: .capsule)

                ForEach(model.filteredCheats) { cheat in
                    CheatCard(
                        cheat: cheat,
                        platform: model.activePlatform,
                        isFavorite: model.isFavorite(cheat),
                        onTap: { onSelect(cheat) },
                        onToggleFavorite: { model.toggleFavorite(cheat) }
                    )
                }
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private var platformToggle: some View {
        Picker("cheats.platform.picker", selection: $model.activePlatform) {
            Text("cheats.platform.ps5").tag(Platform.ps5)
            Text("cheats.platform.xbox").tag(Platform.xbox)
        }
        .pickerStyle(.segmented)
    }
}
```

- [ ] **Step 3: Ajouter les strings au String Catalog**

Dans `NeonCompass/Resources/Localizable.xcstrings` : `cheats.blocksTrophies` = "Blocks trophies", `cheats.search.placeholder` = "Search cheats", `cheats.platform.picker` = "Platform", `cheats.platform.ps5` = "PS5", `cheats.platform.xbox` = "Xbox".

- [ ] **Step 4: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatCard.swift NeonCompass/Features/Cheats/CheatsListView.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: cheats list — glass cards, gamepad glyph chips, platform toggle"
```

---

### Task 5: Mode lecture plein écran

**Files:**
- Create: `NeonCompass/Features/Cheats/CheatReaderView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `Cheat`, `Platform`, `GamepadGlyph`, `CheatsModel` (Tasks 1, 3).
- Produces: `struct CheatReaderView: View` (`init(cheats: [Cheat], startIndex: Int, platform: Platform, onDismiss: @escaping () -> Void)`). Consommé par Task 6.

Pas de test unitaire — vue SwiftUI, `isIdleTimerDisabled` et swipe ne sont vérifiables qu'à l'exécution.

- [ ] **Step 1: Implémenter**

`NeonCompass/Features/Cheats/CheatReaderView.swift` :
```swift
import SwiftUI

struct CheatReaderView: View {
    let cheats: [Cheat]
    let platform: Platform
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(cheats: [Cheat], startIndex: Int, platform: Platform, onDismiss: @escaping () -> Void) {
        self.cheats = cheats
        self.platform = platform
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Text(cheats[currentIndex].effect.en)
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                glyphRows

                Button("cheats.reader.close", action: onDismiss)
                    .buttonStyle(.glassProminent)
                    .tint(NCColor.sunsetMagenta)
            }
            .padding(32)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < 0, currentIndex < cheats.count - 1 {
                        currentIndex += 1
                    } else if value.translation.width > 0, currentIndex > 0 {
                        currentIndex -= 1
                    }
                }
        )
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var glyphRows: some View {
        let sequence = cheats[currentIndex].sequence[platform] ?? []
        return HStack(spacing: 24) {
            ForEach(Array(sequence.enumerated()), id: \.offset) { _, button in
                Image(systemName: GamepadGlyph.systemImage(for: button, platform: platform))
                    .font(.system(size: 64))
                    .foregroundStyle(NCColor.neonCyan)
            }
        }
    }
}
```

Note : `UIApplication.shared.isIdleTimerDisabled` est la seule API UIKit de cette tâche (`isIdleTimerDisabled` n'a pas d'équivalent SwiftUI direct) — un appel isolé, pas une vue UIKit entière, donc pas soumis à la règle "wrapped in one file" du plan 2 (qui concerne les vues/composants UIKit substantiels comme `CATiledLayer`, pas un simple appel de propriété statique).

- [ ] **Step 2: Ajouter la string de fermeture**

Dans `Localizable.xcstrings` : `cheats.reader.close` = "Done".

- [ ] **Step 3: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatReaderView.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: full-screen cheat reader — large glyphs, idle timer disabled, swipe"
```

---

### Task 6: Assemblage — `CheatsScreen` + intégration `RootView`

**Files:**
- Create: `NeonCompass/Features/Cheats/CheatsScreen.swift`
- Modify: `NeonCompass/App/RootView.swift`

**Interfaces:**
- Consumes: tout ce qui précède (Tasks 1-5), `AppTab`, `PlaceholderScreen` (Plan 1).
- Produces: `struct CheatsScreen: View` — remplace `PlaceholderScreen(tab: .cheats)` dans `RootView`.

Pas de test unitaire — assemblage de vues, vérifié par build + vérification visuelle simulateur iPhone et iPad.

- [ ] **Step 1: Implémenter `CheatsScreen`**

`NeonCompass/Features/Cheats/CheatsScreen.swift` :
```swift
import SwiftUI
import SwiftData

struct CheatsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: CheatsModel?
    @State private var readerCheat: Cheat?

    var body: some View {
        Group {
            if let model {
                CheatsListView(model: model) { cheat in
                    readerCheat = cheat
                }
                .fullScreenCover(item: $readerCheat) { cheat in
                    if let index = model.filteredCheats.firstIndex(where: { $0.id == cheat.id }) {
                        CheatReaderView(
                            cheats: model.filteredCheats,
                            startIndex: index,
                            platform: model.activePlatform,
                            onDismiss: { readerCheat = nil }
                        )
                    }
                }
            } else {
                ProgressView()
                    .task { await loadModel() }
            }
        }
    }

    private func loadModel() async {
        guard model == nil else { return }
        let contentStore = CheatContentStore(
            remote: FirestoreCheatRepository(),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = CheatsModel(cheats: contentStore.cheats, modelContext: modelContext)
        try? await contentStore.syncIfNeeded()
        model?.updateCheats(contentStore.cheats)
    }
}
```

Note : contrairement à `MapScreen` (plan 3), cette tâche n'a pas besoin du guard `FirebaseAvailability.isConfigured` — Firebase est maintenant configuré de manière permanente depuis le plan 3 (Task 7, `FirebaseApp.configure()` appelé une fois au lancement de l'app), donc tout écran créé après ce plan peut construire des types Firebase-backed directement sans risque du crash découvert au plan 3.

- [ ] **Step 2: Remplacer le placeholder dans `RootView`**

Dans `NeonCompass/App/RootView.swift`, étendre la fonction `screen(for:)` (déjà introduite au plan 2 pour `.map`) :
```swift
    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .map: MapScreen()
        case .cheats: CheatsScreen()
        default: PlaceholderScreen(tab: tab)
        }
    }
```

- [ ] **Step 3: Build et vérification visuelle**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

Puis lancement simulateur (iPhone et iPad) : onglet Cheats affiche la liste (vide tant qu'aucun cheat n'est publié sur Firestore — comportement attendu, cf. plan 3), toggle PS5/Xbox fonctionnel, favoris épinglables. Pour une vérification visuelle avec du contenu réel, publier temporairement `content/cheats/cheat_sample_placeholder.json` (en alignant d'abord sa séquence Xbox sur le schéma Swift — remplacer `"lb"` par `"l1"`, cf. note Task 1) via `node tools/content-cli/cli.js publish`, vérifier le rendu, puis revenir en `draft` et nettoyer le document Firestore de test (même discipline que le plan 3).

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatsScreen.swift NeonCompass/App/RootView.swift
git commit -m "feat: wire CheatsScreen into RootView, replacing cheats placeholder"
```

---

## Self-Review

**Couverture spec** : cartes glass avec chips de glyphes manette (Task 4) ✓, toggle global PS5/Xbox (Task 3-4) ✓, badge « bloque les trophées » (Task 4) ✓, recherche et catégories (Task 3) ✓, favoris épinglés en tête (Task 3-4) ✓, mode lecture plein écran avec glyphes énormes, écran maintenu allumé, swipe (Task 5) ✓.

**Cohérence des types** : `Cheat`/`CheatCategory`/`Platform`/`GamepadButton` (Task 1) réutilisés tels quels dans `CheatContentStore` (Task 2), `CheatsModel` (Task 3), `CheatCard`/`CheatsListView`/`CheatReaderView` (Tasks 4-5) — aucune redéfinition divergente. `ContentVersionProviding`/`RemoteConfigVersionProvider` (plan 3) réutilisés sans modification, confirmant qu'une seule version de contenu globale gouverne POI et cheats.

**IP** : aucun glyphe/logo propriétaire — uniquement des SF Symbols génériques, vérifié par test (Task 1). Aucune marque Rockstar dans les strings/identifiants.

**Dette assumée** : duplication délibérée du pattern `ContentStore`/`CacheEntry`/`RemoteRepository` entre POI (plan 3) et Cheat (ce plan) — généralisation prévue à l'apparition d'un 3ᵉ consommateur (Guides, plan 3c), pas avant.
