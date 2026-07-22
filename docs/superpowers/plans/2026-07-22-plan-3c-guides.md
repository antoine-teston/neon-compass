# Plan 3c — Guides (Neon Compass v1.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Les guides comme seconde section de l'onglet Cheats & Guides (spec §5 : « un onglet, deux sections ») — chapitres (histoire, side content, débutant, argent), rendu Markdown natif, lecture hors-ligne après cache.

**Architecture:** Réutilise l'infrastructure de sync du plan 3 une troisième fois (`GuideContentStore`, quasi-identique à `POIContentStore`/`CheatContentStore`). **Ce plan est le point de bascule de la règle de trois annoncée aux plans 3/3b** : avec Guides comme 3ᵉ consommateur du même pattern, la duplication n'est plus généralisée immédiatement dans ce plan (garder ce plan scopé à la fonctionnalité Guides, pas à un refactor transverse) mais **explicitement signalée en fin de plan** comme prête pour un plan de consolidation dédié (`ContentStore<Item>` générique remplaçant les trois implémentations dupliquées). Le rendu Markdown est natif SwiftUI (`AttributedString(markdown:)`, iOS 15+) — pas de dépendance tierce. L'intégration UI ajoute un sélecteur de section dans `CheatsScreen` (déjà construit au plan 3b) plutôt que de créer un nouvel onglet, conformément au spec.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + `@Observable`, SwiftData, Firebase Firestore/Remote Config (déjà configuré), Swift Testing.

## Global Constraints

- Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`.
- Firebase isolé derrière des protocoles dans `Core/Content/`.
- Toute string visible passe par le String Catalog.
- Aucune marque Rockstar dans le code, les identifiants, les strings ou les assets.
- Mode sombre uniquement ; glow limité à 3 accents par écran.
- Tests : Swift Testing (`import Testing`), jamais XCTest.
- Commandes de vérification : `Scripts/test.sh`, `Scripts/build.sh`.

---

### Task 1: Modèle `Guide`

**Files:**
- Create: `NeonCompass/Core/Guides/Guide.swift`
- Test: `NeonCompassTests/Guides/GuideTests.swift`

**Interfaces:**
- Consumes: `LocalizedText` (Plan 2, réutilisé tel quel).
- Produces: `enum GuideChapter: String, CaseIterable, Codable, Sendable` (`story, sideContent, beginner, money`) ; `struct Guide: Codable, Equatable, Identifiable, Sendable` (`id: String, chapter: GuideChapter, title: LocalizedText, body: LocalizedText`). Consommé par Task 2 (store), Task 3 (liste + détail).

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Guides/GuideTests.swift` :
```swift
import Testing
import Foundation
@testable import NeonCompass

struct GuideTests {
    @Test func decodesGuideIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "guide_getting_started",
            "chapter": "beginner",
            "title": {"en": "Getting Started", "fr": "Premiers pas"},
            "body": {"en": "# Welcome\\n\\nThis is a sample guide."},
            "status": "draft"
        }
        """.utf8)
        let guide = try JSONDecoder().decode(Guide.self, from: json)
        #expect(guide.id == "guide_getting_started")
        #expect(guide.chapter == .beginner)
        #expect(guide.title.resolved(for: "fr") == "Premiers pas")
        #expect(guide.body.en.contains("Welcome"))
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'Guide' in scope`

- [ ] **Step 3: Implémenter**

`NeonCompass/Core/Guides/Guide.swift` :
```swift
import Foundation

enum GuideChapter: String, CaseIterable, Codable, Sendable {
    case story, sideContent, beginner, money
}

/// Champs pipeline-only du schéma (`status`) ignorés au décodage — même
/// stratégie que POI (plan 2) et Cheat (plan 3b).
struct Guide: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let chapter: GuideChapter
    let title: LocalizedText
    let body: LocalizedText
}
```

Note : `body` est un texte Markdown potentiellement long (plusieurs paragraphes) — `LocalizedText` (déjà générique, simple wrapper de `String`) le supporte sans modification.

- [ ] **Step 4: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Guides NeonCompassTests/Guides
git commit -m "feat: Guide model (chapters, localized Markdown body)"
```

---

### Task 2: `GuideContentStore` — cache SwiftData + sync versionné

**Files:**
- Create: `NeonCompass/Core/Content/GuideRemoteRepository.swift`, `NeonCompass/Core/Content/FirestoreGuideRepository.swift`, `NeonCompass/Core/Content/GuideCacheEntry.swift`, `NeonCompass/Core/Content/GuideContentStore.swift`
- Test: `NeonCompassTests/Content/GuideContentStoreTests.swift`

**Interfaces:**
- Consumes: `Guide` (Task 1), `ContentVersionProviding` (plan 3, réutilisé tel quel).
- Produces: `protocol GuideRemoteRepository: Sendable { func fetchAll() async throws -> [Guide] }` ; `final class FirestoreGuideRepository: GuideRemoteRepository` (miroir de `FirestorePOIRepository`/`FirestoreCheatRepository`, décodage tolérant document-par-document) ; `@Model final class GuideCacheEntry` (miroir de `POICacheEntry`/`CheatCacheEntry`) ; `@Observable @MainActor final class GuideContentStore` (miroir de `POIContentStore`/`CheatContentStore`). Consommé par Task 4.

**⚠️ Troisième duplication du pattern `ContentStore`/`CacheEntry`/`RemoteRepository`** (après POI au plan 3, Cheat au plan 3b). Conformément à la règle de trois annoncée dans ces deux plans, cette duplication n'est **plus** acceptée comme un simple différé — voir la Self-Review en fin de ce plan pour la tâche de consolidation à planifier immédiatement après.

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Content/GuideContentStoreTests.swift` :
```swift
import Testing
import SwiftData
@testable import NeonCompass

final class FakeGuideRemoteRepository: GuideRemoteRepository {
    var guidesToReturn: [Guide] = []
    private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [Guide] {
        fetchCallCount += 1
        return guidesToReturn
    }
}

@MainActor
struct GuideContentStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([GuideCacheEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func sampleGuide(id: String) -> Guide {
        Guide(id: id, chapter: .beginner,
              title: LocalizedText(en: "Sample", fr: nil, es: nil, it: nil, de: nil),
              body: LocalizedText(en: "# Sample body", fr: nil, es: nil, it: nil, de: nil))
    }

    @Test func startsEmptyWithNoCacheAndVersionZero() {
        let remote = FakeGuideRemoteRepository()
        let version = FakeContentVersionProvider()
        let store = GuideContentStore(remote: remote, versionProvider: version, modelContext: makeContext())
        #expect(store.guides.isEmpty)
    }

    @Test func syncFetchesAndCachesWhenRemoteVersionIsNewer() async throws {
        let remote = FakeGuideRemoteRepository()
        remote.guidesToReturn = [sampleGuide(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let store = GuideContentStore(remote: remote, versionProvider: version, modelContext: makeContext())

        try await store.syncIfNeeded()

        #expect(store.guides.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func syncIsNoOpWhenVersionUnchanged() async throws {
        let remote = FakeGuideRemoteRepository()
        remote.guidesToReturn = [sampleGuide(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()
        let store = GuideContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await store.syncIfNeeded()

        let secondStore = GuideContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await secondStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)
    }

    @Test func loadsFromCacheOnInitWithoutNetworkCall() async throws {
        let remote = FakeGuideRemoteRepository()
        remote.guidesToReturn = [sampleGuide(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let firstStore = GuideContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await firstStore.syncIfNeeded()

        let secondStore = GuideContentStore(remote: remote, versionProvider: version, modelContext: context)
        #expect(secondStore.guides.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }
}
```

Note : `FakeContentVersionProvider` est déjà défini dans `NeonCompassTests/Content/FakesTests.swift` (plan 3), visible ici sans réimport (même test target).

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'GuideContentStore' in scope`

- [ ] **Step 3: Implémenter**

`NeonCompass/Core/Content/GuideRemoteRepository.swift` :
```swift
import Foundation

protocol GuideRemoteRepository: Sendable {
    func fetchAll() async throws -> [Guide]
}
```

`NeonCompass/Core/Content/FirestoreGuideRepository.swift` :
```swift
import FirebaseFirestore

final class FirestoreGuideRepository: GuideRemoteRepository {
    private let collection: CollectionReference

    init(firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection("guides")
    }

    func fetchAll() async throws -> [Guide] {
        let snapshot = try await collection.getDocuments()
        return snapshot.documents.compactMap { document in
            do {
                let data = try JSONSerialization.data(withJSONObject: document.data())
                return try JSONDecoder().decode(Guide.self, from: data)
            } catch {
                print("FirestoreGuideRepository: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
```

`NeonCompass/Core/Content/GuideCacheEntry.swift` :
```swift
import Foundation
import SwiftData

@Model
final class GuideCacheEntry {
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

`NeonCompass/Core/Content/GuideContentStore.swift` :
```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class GuideContentStore {
    private static let collectionName = "guides"

    private(set) var guides: [Guide]

    private let remote: GuideRemoteRepository
    private let versionProvider: ContentVersionProviding
    private let modelContext: ModelContext

    init(remote: GuideRemoteRepository, versionProvider: ContentVersionProviding, modelContext: ModelContext) {
        self.remote = remote
        self.versionProvider = versionProvider
        self.modelContext = modelContext
        self.guides = Self.loadCached(from: modelContext)
    }

    func syncIfNeeded() async throws {
        let remoteVersion = try await versionProvider.currentVersion()
        let localVersion = Self.cachedVersion(from: modelContext)
        guard remoteVersion > localVersion else { return }

        let fetched = try await remote.fetchAll()
        let data = try JSONEncoder().encode(fetched)

        let name = Self.collectionName
        let descriptor = FetchDescriptor<GuideCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.json = data
            existing.version = remoteVersion
        } else {
            modelContext.insert(GuideCacheEntry(collectionName: Self.collectionName, json: data, version: remoteVersion))
        }
        try modelContext.save()

        guides = fetched
    }

    private static func loadCached(from modelContext: ModelContext) -> [Guide] {
        let name = collectionName
        let descriptor = FetchDescriptor<GuideCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let decoded = try? JSONDecoder().decode([Guide].self, from: entry.json) else {
            return []
        }
        return decoded
    }

    private static func cachedVersion(from modelContext: ModelContext) -> Int {
        let name = collectionName
        let descriptor = FetchDescriptor<GuideCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        return (try? modelContext.fetch(descriptor).first?.version) ?? 0
    }
}
```

- [ ] **Step 4: Enregistrer `GuideCacheEntry` dans le conteneur SwiftData**

Dans `NeonCompass/App/NeonCompassApp.swift`, ajouter `GuideCacheEntry.self` à `.modelContainer(for: [...])`.

- [ ] **Step 5: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Core/Content/GuideRemoteRepository.swift NeonCompass/Core/Content/FirestoreGuideRepository.swift NeonCompass/Core/Content/GuideCacheEntry.swift NeonCompass/Core/Content/GuideContentStore.swift NeonCompass/App/NeonCompassApp.swift NeonCompassTests/Content/GuideContentStoreTests.swift
git commit -m "feat: GuideContentStore — SwiftData cache + version-gated sync (3rd ContentStore duplicate, flagged for consolidation)"
```

---

### Task 3: Liste des chapitres + rendu Markdown natif

**Files:**
- Create: `NeonCompass/Features/Guides/GuidesModel.swift`, `NeonCompass/Features/Guides/GuidesListView.swift`, `NeonCompass/Features/Guides/GuideDetailView.swift`
- Test: `NeonCompassTests/Guides/GuidesModelTests.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `Guide`, `GuideChapter`, `LocalizedText`, `NCColor`/`NCTypography` (Task 1, Plan 1).
- Produces: `@Observable @MainActor final class GuidesModel` (`init(guides: [Guide])`, `func updateGuides(_ newGuides: [Guide])`, `func guides(in chapter: GuideChapter) -> [Guide]`) ; `struct GuidesListView: View` (`init(model: GuidesModel, onSelect: @escaping (Guide) -> Void)`) ; `struct GuideDetailView: View` (`init(guide: Guide)`). Consommé par Task 4.

`GuidesModel` n'a volontairement pas de SwiftData (pas de favoris/progression pour les guides en v1 — juste un regroupement par chapitre, testable sans I/O).

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Guides/GuidesModelTests.swift` :
```swift
import Testing
@testable import NeonCompass

struct GuidesModelTests {
    private func sampleGuides() -> [Guide] {
        [
            Guide(id: "a", chapter: .beginner, title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil),
                  body: LocalizedText(en: "Body A", fr: nil, es: nil, it: nil, de: nil)),
            Guide(id: "b", chapter: .money, title: LocalizedText(en: "Beta", fr: nil, es: nil, it: nil, de: nil),
                  body: LocalizedText(en: "Body B", fr: nil, es: nil, it: nil, de: nil)),
        ]
    }

    @Test func groupsGuidesByChapter() {
        let model = GuidesModel(guides: sampleGuides())
        #expect(model.guides(in: .beginner).map(\.id) == ["a"])
        #expect(model.guides(in: .money).map(\.id) == ["b"])
        #expect(model.guides(in: .story).isEmpty)
    }

    @Test func updateGuidesReplacesContent() {
        let model = GuidesModel(guides: [])
        #expect(model.guides(in: .beginner).isEmpty)
        model.updateGuides(sampleGuides())
        #expect(model.guides(in: .beginner).map(\.id) == ["a"])
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'GuidesModel' in scope`

- [ ] **Step 3: Implémenter `GuidesModel`**

`NeonCompass/Features/Guides/GuidesModel.swift` :
```swift
import Foundation
import Observation

@Observable
@MainActor
final class GuidesModel {
    private(set) var guides: [Guide]

    init(guides: [Guide]) {
        self.guides = guides
    }

    func updateGuides(_ newGuides: [Guide]) {
        guides = newGuides
    }

    func guides(in chapter: GuideChapter) -> [Guide] {
        guides.filter { $0.chapter == chapter }
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Implémenter les vues**

`NeonCompass/Features/Guides/GuideDetailView.swift` :
```swift
import SwiftUI

/// Rendu Markdown natif (AttributedString(markdown:), iOS 15+) — pas de
/// dépendance tierce. Si le texte n'est pas un Markdown valide (cas rare
/// pour du contenu éditorial validé par le CLI admin), on retombe sur le
/// texte brut plutôt que de planter.
struct GuideDetailView: View {
    let guide: Guide

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(guide.title.resolved(for: currentLanguageCode))
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)

                Text(renderedBody)
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private var renderedBody: AttributedString {
        let markdown = guide.body.resolved(for: currentLanguageCode)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}
```

`NeonCompass/Features/Guides/GuidesListView.swift` :
```swift
import SwiftUI

struct GuidesListView: View {
    @Bindable var model: GuidesModel
    let onSelect: (Guide) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(GuideChapter.allCases, id: \.self) { chapter in
                    let chapterGuides = model.guides(in: chapter)
                    if !chapterGuides.isEmpty {
                        chapterSection(chapter, guides: chapterGuides)
                    }
                }
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private func chapterSection(_ chapter: GuideChapter, guides: [Guide]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chapterTitleKey(chapter))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            ForEach(guides) { guide in
                Button {
                    onSelect(guide)
                } label: {
                    Text(guide.title.resolved(for: currentLanguageCode))
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private func chapterTitleKey(_ chapter: GuideChapter) -> LocalizedStringKey {
        switch chapter {
        case .story: "guides.chapter.story"
        case .sideContent: "guides.chapter.sideContent"
        case .beginner: "guides.chapter.beginner"
        case .money: "guides.chapter.money"
        }
    }
}
```

Note : `currentLanguageCode` est dupliqué ici et dans `GuideDetailView.swift` (même petite propriété calculée) — cohérent avec la convention déjà établie par `MapModel`/`CheatsModel` (une propriété par fichier, pas d'abstraction partagée prématurée, cf. plans 3/3b).

- [ ] **Step 6: Ajouter les strings au String Catalog**

Dans `Localizable.xcstrings` : `guides.chapter.story` = "Story", `guides.chapter.sideContent` = "Side Content", `guides.chapter.beginner` = "Beginner", `guides.chapter.money` = "Money".

- [ ] **Step 7: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Features/Guides NeonCompassTests/Guides NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: guides list by chapter + native Markdown detail rendering"
```

---

### Task 4: Intégration — section « Guides » dans l'écran Cheats & Guides

**Files:**
- Modify: `NeonCompass/Features/Cheats/CheatsScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `GuidesModel`, `GuidesListView`, `GuideDetailView`, `GuideContentStore` (Tasks 1-3), `CheatsScreen` existant (plan 3b, non réécrit — seulement étendu).
- Produces: `CheatsScreen` affiche désormais un sélecteur de section (Cheats/Guides) en tête, conformément au spec §5 : « un onglet, deux sections ».

Pas de test unitaire — assemblage de vues, état déjà testé (`CheatsModel` plan 3b, `GuidesModel` Task 3). Vérification par build + vérification visuelle simulateur iPhone et iPad.

- [ ] **Step 1: Ajouter le sélecteur de section et l'état Guides à `CheatsScreen`**

Remplacer le contenu de `NeonCompass/Features/Cheats/CheatsScreen.swift` par :
```swift
import SwiftUI
import SwiftData

private enum CheatsGuidesSection: String, CaseIterable {
    case cheats, guides
}

struct CheatsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: CheatsModel?
    @State private var guidesModel: GuidesModel?
    @State private var readerCheat: Cheat?
    @State private var selectedGuide: Guide?
    @State private var section: CheatsGuidesSection = .cheats

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            Group {
                switch section {
                case .cheats:
                    if let model {
                        cheatsContent(model: model)
                    } else {
                        ProgressView().task { await loadCheatsModel() }
                    }
                case .guides:
                    if let guidesModel {
                        GuidesListView(model: guidesModel) { guide in
                            selectedGuide = guide
                        }
                        .sheet(item: $selectedGuide) { guide in
                            GuideDetailView(guide: guide)
                        }
                    } else {
                        ProgressView().task { await loadGuidesModel() }
                    }
                }
            }
        }
    }

    private var sectionPicker: some View {
        Picker("cheatsGuides.section.picker", selection: $section) {
            Text("cheatsGuides.section.cheats").tag(CheatsGuidesSection.cheats)
            Text("cheatsGuides.section.guides").tag(CheatsGuidesSection.guides)
        }
        .pickerStyle(.segmented)
        .padding(16)
    }

    private func cheatsContent(model: CheatsModel) -> some View {
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
    }

    private func loadCheatsModel() async {
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

    private func loadGuidesModel() async {
        guard guidesModel == nil else { return }
        let contentStore = GuideContentStore(
            remote: FirestoreGuideRepository(),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        guidesModel = GuidesModel(guides: contentStore.guides)
        try? await contentStore.syncIfNeeded()
        guidesModel?.updateGuides(contentStore.guides)
    }
}
```

Note : le corps de `cheatsContent`/`loadCheatsModel` est repris à l'identique du `CheatsScreen` du plan 3b (aucune logique cheats modifiée, seulement déplacée dans une méthode nommée pour cohabiter avec la section guides).

- [ ] **Step 2: Ajouter les strings du sélecteur**

Dans `Localizable.xcstrings` : `cheatsGuides.section.picker` = "Section", `cheatsGuides.section.cheats` = "Cheats", `cheatsGuides.section.guides` = "Guides".

- [ ] **Step 3: Build et vérification visuelle**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

Puis lancement simulateur (iPhone et iPad) : onglet Cheats & Guides affiche le sélecteur de section en tête, bascule Cheats ↔ Guides fonctionnelle, section Guides vide tant qu'aucun guide n'est publié sur Firestore (comportement attendu). Vérifier aussi que la section Cheats fonctionne toujours exactement comme au plan 3b (non-régression).

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatsScreen.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: add Guides section to Cheats & Guides screen (spec: one tab, two sections)"
```

---

## Self-Review

**Couverture spec** : chapitres (histoire, side content, débutant, argent) ✓, rendu Markdown natif ✓, lecture hors-ligne après cache (`GuideContentStore`, offline-first comme POI/Cheat) ✓, « un onglet, deux sections » — respecté en étendant `CheatsScreen` plutôt qu'en créant un nouvel onglet ✓.

**Cohérence des types** : `Guide`/`GuideChapter`/`LocalizedText` (Task 1) réutilisés tels quels dans `GuideContentStore` (Task 2), `GuidesModel`/`GuidesListView`/`GuideDetailView` (Tasks 3-4).

**Non-régression** : `CheatsScreen` (plan 3b) est étendu, pas réécrit — la logique cheats (`cheatsContent`/`loadCheatsModel`) est reprise à l'identique, seule la structure englobante change (ajout du picker de section).

**Localisation** : leçon du plan 3b appliquée directement dans ce plan — `GuidesListView`/`GuideDetailView` utilisent `resolved(for:)` dès l'écriture initiale, pas de correctif après coup.

**Dette signalée pour un plan futur (pas de ce plan)** :
1. **Consolidation `ContentStore`** — avec Guides, le pattern `ContentStore`/`CacheEntry`/`RemoteRepository` est maintenant dupliqué 3 fois (POI, Cheat, Guide), identique à un renommage de type près. Un plan de refactor dédié (généraliser en `ContentStore<Item: Codable & Sendable>` + `CacheEntry` unique + protocole générique) devrait suivre immédiatement après ce plan, avant qu'un 4ᵉ type de contenu n'apparaisse.
2. **Toggle favoris non-réactif** (signalé au plan 3b) — toujours non traité, concerne `MapModel`/`CheatsModel`, à regrouper avec la consolidation ci-dessus ou le plan 4 (Progression).
3. **Migration français-primaire** (décidée en session, documentée CLAUDE.md) — toujours non appliquée, ce plan reste anglais-primaire comme les plans 2/3/3b.
