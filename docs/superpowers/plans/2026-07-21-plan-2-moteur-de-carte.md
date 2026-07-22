# Plan 2 — Moteur de carte (Neon Compass v1.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un onglet Carte fonctionnel : viewer tuilé zoom/pan (CATiledLayer) affichant l'artwork généré par `tools/basemap/`, POI en coordonnées normalisées avec filtres/recherche, fiche POI en Liquid Glass avec bouton « Trouvé » persisté en SwiftData, et pins personnels posables par appui long.

**Architecture:** Le rendu tuilé est la seule pièce UIKit du plan (CATiledLayer n'a pas d'équivalent SwiftUI), isolée dans un fichier unique et wrappée en `UIViewRepresentable`. Tout le reste (modèles, filtres, fiche POI, pins) est SwiftUI + `@Observable`. Les POI viennent d'un fixture JSON embarqué dans l'app (`Resources/POI/seed-poi.json`) — la synchronisation Firestore arrive au plan 3 ; ce plan pose le modèle `POI` au format déjà utilisé par le pipeline de contenu (`content/schema/poi.schema.json`), donc rien à changer côté décodage quand la vraie source arrivera. « Trouvé » et les pins personnels utilisent SwiftData, seule source de vérité locale (réutilisée telle quelle par la Progression au plan 4).

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + `@Observable`, SwiftData, UIKit (`CATiledLayer` uniquement, wrappé), Swift Testing.

**Interprétation d'une zone floue du roadmap :** « pins perso » n'est pas détaillé dans le spec (seulement dans `docs/superpowers/plans/2026-07-19-v1-roadmap.md`). Interprété ici comme un marqueur strictement local (titre + position, SwiftData, pas de compte, pas de sync serveur) — à distinguer de la contribution communautaire du spec §5 (appui long → proposer un spot, votes, modération), qui requiert Sign in with Apple et arrive au plan 5.

## Global Constraints

- Cible : iOS/iPadOS 26.0 minimum, iPhone + iPad, pas de Mac Catalyst.
- Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`.
- Aucune marque Rockstar dans le code, les identifiants, les strings ou les assets.
- Toute string visible passe par le String Catalog (`NeonCompass/Resources/Localizable.xcstrings`) — pas de littéraux en dur dans les vues.
- SwiftUI uniquement ; UIKit seulement si une API l'impose (ici : `CATiledLayer`), wrappé dans un fichier unique.
- Tests : Swift Testing (`import Testing`), jamais XCTest.
- Mode sombre uniquement ; glow limité à 3 accents par écran.
- POI en coordonnées normalisées (0-1), indépendantes de l'artwork (spec §4).
- Commandes de vérification : `Scripts/test.sh` (génère le projet et lance les tests), `Scripts/build.sh`.

---

### Task 1: Tuiles bundlées + `TileManifest`

**Files:**
- Create: `NeonCompass/Resources/MapTiles/` (pyramide de tuiles générée), `NeonCompass/Core/Map/TileManifest.swift`
- Test: `NeonCompassTests/Map/TileManifestTests.swift`
- Modify: `project.yml`

**Interfaces:**
- Produces: `struct TileManifest: Codable, Equatable, Sendable` (`tileSize: Int`, `maxZoom: Int`, `tileCount: Int`) — consommé par Task 5 (viewer tuilé) et Task 4 (géométrie des pins).

- [ ] **Step 1: Générer la pyramide de tuiles dans les ressources de l'app**

Run (depuis la racine du repo) :
```bash
node tools/basemap/tile.js tools/basemap/leonida-placeholder.svg NeonCompass/Resources/MapTiles 3
```
Expected: `85 tiles + manifest.json → NeonCompass/Resources/MapTiles` (mêmes tuiles placeholder déjà vérifiées lors de la mise en place de l'outillage).

- [ ] **Step 2: Déclarer le dossier comme folder reference dans `project.yml`**

Remplacer la liste `sources: [NeonCompass]` de la cible `NeonCompass` par :
```yaml
targets:
  NeonCompass:
    type: application
    platform: iOS
    sources:
      - path: NeonCompass
        excludes:
          - "Resources/MapTiles/**"
      - path: NeonCompass/Resources/MapTiles
        type: folder
```
(La cible `NeonCompassTests` ne change pas.) Le `type: folder` préserve la hiérarchie `z/x/y` dans le bundle — indispensable pour que `Bundle.main.url(forResource:withExtension:subdirectory:)` retrouve une tuile précise (utilisé Task 5).

- [ ] **Step 3: Écrire le test du manifest (failing)**

`NeonCompassTests/Map/TileManifestTests.swift` :
```swift
import Testing
import Foundation
@testable import NeonCompass

struct TileManifestTests {
    @Test func decodesManifest() throws {
        let json = Data("""
        {"tileSize": 256, "maxZoom": 3, "tileCount": 85, "source": "leonida-placeholder.svg", "sourceSha256": "abc123"}
        """.utf8)
        let manifest = try JSONDecoder().decode(TileManifest.self, from: json)
        #expect(manifest.tileSize == 256)
        #expect(manifest.maxZoom == 3)
        #expect(manifest.tileCount == 85)
    }
}
```

- [ ] **Step 4: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'TileManifest' in scope`

- [ ] **Step 5: Implémenter `TileManifest`**

`NeonCompass/Core/Map/TileManifest.swift` :
```swift
import Foundation

/// Décrit une pyramide de tuiles générée par tools/basemap/tile.js.
/// Champs additionnels du JSON (source, sourceSha256) sont ignorés au décodage.
struct TileManifest: Codable, Equatable, Sendable {
    let tileSize: Int
    let maxZoom: Int
    let tileCount: Int

    static func load(from bundle: Bundle = .main) -> TileManifest? {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "MapTiles"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TileManifest.self, from: data)
    }
}
```

- [ ] **Step 6: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Resources/MapTiles NeonCompass/Core/Map/TileManifest.swift NeonCompassTests/Map/TileManifestTests.swift project.yml
git commit -m "feat: bundle placeholder tile pyramid + TileManifest"
```

---

### Task 2: Modèle `POI` + fixture locale

**Files:**
- Create: `NeonCompass/Core/Map/POI.swift`, `NeonCompass/Resources/POI/seed-poi.json`
- Test: `NeonCompassTests/Map/POITests.swift`

**Interfaces:**
- Produces: `enum POICategory: String, CaseIterable, Codable, Sendable` (`landmark, collectible, activity, safehouse, vehicle, event` — même énumération que `content/schema/poi.schema.json`) ; `struct NormalizedPoint: Codable, Equatable, Sendable` (`x: Double, y: Double`) ; `struct LocalizedText: Codable, Equatable, Sendable` (`en: String`, `fr/es/it/de: String?`, `func resolved(for languageCode: String) -> String`) ; `struct POI: Codable, Equatable, Identifiable, Sendable` (`id, category, position, title, note: LocalizedText?`) ; `enum POILoader` (`static func decode(_ data: Data) throws -> [POI]`, `static func loadSeed(from bundle: Bundle = .main) throws -> [POI]`). Consommé par Task 3 (MapModel), Task 4 (géométrie), Task 6 (fiche POI).

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Map/POITests.swift` :
```swift
import Testing
import Foundation
@testable import NeonCompass

struct POITests {
    @Test func resolvedFallsBackToEnglish() {
        let text = LocalizedText(en: "Lighthouse", fr: "Phare", es: nil, it: nil, de: nil)
        #expect(text.resolved(for: "fr") == "Phare")
        #expect(text.resolved(for: "es") == "Lighthouse")
        #expect(text.resolved(for: "en") == "Lighthouse")
    }

    @Test func decodesPOIArrayIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        [{
            "id": "poi_sample_lighthouse",
            "category": "landmark",
            "position": {"x": 0.7312, "y": 0.4147},
            "title": {"en": "Old Harbor Lighthouse", "fr": "Phare du vieux port"},
            "note": {"en": "Sample note"},
            "status": "draft",
            "sources": ["internal:fixture"]
        }]
        """.utf8)
        let pois = try POILoader.decode(json)
        #expect(pois.count == 1)
        #expect(pois[0].id == "poi_sample_lighthouse")
        #expect(pois[0].category == .landmark)
        #expect(abs(pois[0].position.x - 0.7312) < 0.0001)
        #expect(pois[0].title.resolved(for: "fr") == "Phare du vieux port")
    }

    @Test func seedFileIsValidJSON() throws {
        // Vérifie que le fixture livré avec l'app est un JSON POI[] valide, en
        // lisant le fichier directement depuis le repo plutôt que via Bundle.main
        // (NeonCompassTests n'est pas hébergé dans le process app — TEST_HOST non
        // configuré — donc Bundle.main pointe vers le runner de test, pas l'app).
        // Le chargement réel via Bundle.main (POILoader.loadSeed) est couvert par
        // le build + la vérification visuelle de la Task 9.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NeonCompass/Resources/POI/seed-poi.json")
        let data = try Data(contentsOf: url)
        let pois = try POILoader.decode(data)
        #expect(pois.count >= 2)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'LocalizedText' in scope`

- [ ] **Step 3: Implémenter le modèle**

`NeonCompass/Core/Map/POI.swift` :
```swift
import Foundation

enum POICategory: String, CaseIterable, Codable, Sendable {
    case landmark, collectible, activity, safehouse, vehicle, event
}

struct NormalizedPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

/// Miroir du schéma `content/schema/poi.schema.json` $defs.localized :
/// EN obligatoire, les autres langues optionnelles avec repli sur EN.
struct LocalizedText: Codable, Equatable, Sendable {
    let en: String
    let fr: String?
    let es: String?
    let it: String?
    let de: String?

    func resolved(for languageCode: String) -> String {
        switch languageCode {
        case "fr": fr ?? en
        case "es": es ?? en
        case "it": it ?? en
        case "de": de ?? en
        default: en
        }
    }
}

/// Champs pipeline-only du schéma (`status`, `sources`) sont absents ici :
/// Codable ignore silencieusement les clés JSON inconnues au décodage.
struct POI: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: POICategory
    let position: NormalizedPoint
    let title: LocalizedText
    let note: LocalizedText?
}

enum POILoader {
    enum LoaderError: Error { case missingResource }

    static func decode(_ data: Data) throws -> [POI] {
        try JSONDecoder().decode([POI].self, from: data)
    }

    static func loadSeed(from bundle: Bundle = .main) throws -> [POI] {
        guard let url = bundle.url(forResource: "seed-poi", withExtension: "json", subdirectory: "POI") else {
            throw LoaderError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }
}
```

- [ ] **Step 4: Créer le fixture embarqué**

`NeonCompass/Resources/POI/seed-poi.json` :
```json
[
  {
    "id": "poi_sample_lighthouse",
    "category": "landmark",
    "position": { "x": 0.62, "y": 0.30 },
    "title": { "en": "Old Harbor Lighthouse", "fr": "Phare du vieux port" },
    "note": { "en": "Sample POI used to validate the map engine before launch." }
  },
  {
    "id": "poi_sample_dock",
    "category": "activity",
    "position": { "x": 0.55, "y": 0.55 },
    "title": { "en": "Fishing Dock", "fr": "Quai de pêche" },
    "note": { "en": "Sample POI used to validate the map engine before launch." }
  },
  {
    "id": "poi_sample_overlook",
    "category": "collectible",
    "position": { "x": 0.40, "y": 0.20 },
    "title": { "en": "Hillside Overlook", "fr": "Point de vue" },
    "note": { "en": "Sample POI used to validate the map engine before launch." }
  }
]
```

- [ ] **Step 5: Ajouter le dossier `POI` au bundle dans `project.yml`**

Un seul fichier plat, pas besoin de folder reference (contrairement à `MapTiles`) — il est déjà inclus via l'entrée `path: NeonCompass` du Step 2 de la Task 1, tant que `Resources/POI/**` n'est pas exclu. Aucun changement supplémentaire requis.

- [ ] **Step 6: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Core/Map/POI.swift NeonCompass/Resources/POI/seed-poi.json NeonCompassTests/Map/POITests.swift
git commit -m "feat: POI model + localized text + bundled seed fixture"
```

---

### Task 3: SwiftData — `FoundEntry`, `PersonalPin`, `MapModel`

**Files:**
- Create: `NeonCompass/Core/Map/FoundEntry.swift`, `NeonCompass/Core/Map/PersonalPin.swift`, `NeonCompass/Features/Map/MapModel.swift`
- Modify: `NeonCompass/App/NeonCompassApp.swift`
- Test: `NeonCompassTests/Map/MapModelTests.swift`

**Interfaces:**
- Consumes: `POI`, `POICategory` (Task 2).
- Produces: `@Model final class FoundEntry` (`poiID: String` unique, `foundAt: Date`) ; `@Model final class PersonalPin: Identifiable` (`id: UUID`, `x: Double`, `y: Double`, `title: String`, `createdAt: Date`) ; `@Observable @MainActor final class MapModel` (`init(pois: [POI], modelContext: ModelContext)`, `var activeCategories: Set<POICategory>`, `var searchQuery: String`, `var selectedPOI: POI?`, `var filteredPOIs: [POI]` (computed), `func isFound(_ poi: POI) -> Bool`, `func toggleFound(_ poi: POI)`, `var personalPins: [PersonalPin]` (computed via fetch), `func addPersonalPin(at point: NormalizedPoint, title: String)`, `func deletePersonalPin(_ pin: PersonalPin)`). Consommé par Task 6 (fiche POI), Task 7 (filtres), Task 8 (pins), Task 9 (RootView).

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Map/MapModelTests.swift` :
```swift
import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct MapModelTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self, PersonalPin.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func samplePOIs() -> [POI] {
        [
            POI(id: "a", category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
                title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil),
            POI(id: "b", category: .collectible, position: NormalizedPoint(x: 0.2, y: 0.2),
                title: LocalizedText(en: "Beta", fr: nil, es: nil, it: nil, de: nil), note: nil),
        ]
    }

    @Test func filtersByActiveCategory() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        model.activeCategories = [.landmark]
        #expect(model.filteredPOIs.map(\.id) == ["a"])
    }

    @Test func filtersBySearchQuery() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        model.searchQuery = "bet"
        #expect(model.filteredPOIs.map(\.id) == ["b"])
    }

    @Test func toggleFoundPersistsAndIsIdempotentPerPOI() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let poi = samplePOIs()[0]
        #expect(!model.isFound(poi))
        model.toggleFound(poi)
        #expect(model.isFound(poi))
        model.toggleFound(poi)
        #expect(!model.isFound(poi))
    }

    @Test func addAndDeletePersonalPin() {
        let model = MapModel(pois: [], modelContext: makeContext())
        #expect(model.personalPins.isEmpty)
        model.addPersonalPin(at: NormalizedPoint(x: 0.5, y: 0.5), title: "My spot")
        #expect(model.personalPins.count == 1)
        #expect(model.personalPins[0].title == "My spot")
        model.deletePersonalPin(model.personalPins[0])
        #expect(model.personalPins.isEmpty)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'FoundEntry' in scope`

- [ ] **Step 3: Implémenter les modèles SwiftData**

`NeonCompass/Core/Map/FoundEntry.swift` :
```swift
import Foundation
import SwiftData

/// Source de vérité unique carte↔checklists (spec §5, réutilisée au plan 4).
@Model
final class FoundEntry {
    @Attribute(.unique) var poiID: String
    var foundAt: Date

    init(poiID: String, foundAt: Date = .now) {
        self.poiID = poiID
        self.foundAt = foundAt
    }
}
```

`NeonCompass/Core/Map/PersonalPin.swift` :
```swift
import Foundation
import SwiftData

/// Marqueur strictement local — distinct de la contribution communautaire
/// (spec §5), qui requiert un compte et arrive au plan 5.
@Model
final class PersonalPin: Identifiable {
    var id: UUID
    var x: Double
    var y: Double
    var title: String
    var createdAt: Date

    init(id: UUID = UUID(), x: Double, y: Double, title: String, createdAt: Date = .now) {
        self.id = id
        self.x = x
        self.y = y
        self.title = title
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Implémenter `MapModel`**

`NeonCompass/Features/Map/MapModel.swift` :
```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class MapModel {
    private(set) var pois: [POI]
    var activeCategories: Set<POICategory>
    var searchQuery: String = ""
    var selectedPOI: POI?

    private let modelContext: ModelContext

    init(pois: [POI], modelContext: ModelContext) {
        self.pois = pois
        self.activeCategories = Set(POICategory.allCases)
        self.modelContext = modelContext
    }

    var filteredPOIs: [POI] {
        pois.filter { poi in
            activeCategories.contains(poi.category)
                && (searchQuery.isEmpty || poi.title.en.localizedCaseInsensitiveContains(searchQuery))
        }
    }

    func isFound(_ poi: POI) -> Bool {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    func toggleFound(_ poi: POI) {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FoundEntry(poiID: poi.id))
        }
        try? modelContext.save()
    }

    var personalPins: [PersonalPin] {
        let descriptor = FetchDescriptor<PersonalPin>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func addPersonalPin(at point: NormalizedPoint, title: String) {
        modelContext.insert(PersonalPin(x: point.x, y: point.y, title: title))
        try? modelContext.save()
    }

    func deletePersonalPin(_ pin: PersonalPin) {
        modelContext.delete(pin)
        try? modelContext.save()
    }
}
```

- [ ] **Step 5: Enregistrer le conteneur SwiftData au niveau App**

Dans `NeonCompass/App/NeonCompassApp.swift`, ajouter le modifier `.modelContainer` :
```swift
import SwiftUI

@main
struct NeonCompassApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FoundEntry.self, PersonalPin.self])
    }
}
```

- [ ] **Step 6: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Core/Map/FoundEntry.swift NeonCompass/Core/Map/PersonalPin.swift NeonCompass/Features/Map/MapModel.swift NeonCompass/App/NeonCompassApp.swift NeonCompassTests/Map/MapModelTests.swift
git commit -m "feat: SwiftData FoundEntry/PersonalPin + MapModel"
```

---

### Task 4: `MapGeometry` — conversion coordonnées normalisées ↔ écran

**Files:**
- Create: `NeonCompass/Core/Map/MapGeometry.swift`
- Test: `NeonCompassTests/Map/MapGeometryTests.swift`

**Interfaces:**
- Consumes: `TileManifest` (Task 1), `NormalizedPoint` (Task 2).
- Produces: `struct MapViewport: Equatable, Sendable` (`var zoomScale: CGFloat = 1`, `var contentOffset: CGPoint = .zero`) ; `enum MapGeometry` (`static func fullSize(for manifest: TileManifest) -> CGFloat`, `static func screenPosition(for point: NormalizedPoint, manifest: TileManifest, viewport: MapViewport) -> CGPoint`, `static func normalizedPoint(fromCanvasPoint point: CGPoint, manifest: TileManifest) -> NormalizedPoint`). `screenPosition` convertit vers l'espace de la vue SwiftUI superposée (dimensions du viewport visible, dépend du zoom/pan) — utilisé Task 6/8 pour positionner les pins. `normalizedPoint(fromCanvasPoint:)` convertit depuis l'espace du canvas UIKit plein-résolution (indépendant du zoom/pan courant, cf. Task 5) — utilisé Task 9 pour la pose de pin personnel par appui long. Les deux espaces sont distincts ; ne pas les mélanger.

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Map/MapGeometryTests.swift` :
```swift
import Testing
import CoreGraphics
@testable import NeonCompass

struct MapGeometryTests {
    let manifest = TileManifest(tileSize: 256, maxZoom: 3, tileCount: 85)

    @Test func fullSizeIsTileSizeTimesTwoPowMaxZoom() {
        #expect(MapGeometry.fullSize(for: manifest) == 256 * 8)
    }

    @Test func screenPositionAtOriginNoZoomNoOffset() {
        let viewport = MapViewport(zoomScale: 1, contentOffset: .zero)
        let p = MapGeometry.screenPosition(for: NormalizedPoint(x: 0, y: 0), manifest: manifest, viewport: viewport)
        #expect(p == .zero)
    }

    @Test func screenPositionScalesWithZoomAndOffset() {
        let viewport = MapViewport(zoomScale: 0.5, contentOffset: CGPoint(x: 10, y: 20))
        let p = MapGeometry.screenPosition(for: NormalizedPoint(x: 0.5, y: 0.5), manifest: manifest, viewport: viewport)
        // fullSize = 2048 ; point brut = (1024, 1024) ; *0.5 zoom - offset
        #expect(p == CGPoint(x: 1024 * 0.5 - 10, y: 1024 * 0.5 - 20))
    }

    @Test func normalizedPointFromCanvasPointIsZoomIndependent() {
        // fullSize = 256 * 2^3 = 2048 — le canvas est plein-résolution,
        // donc cette conversion ne dépend d'aucun MapViewport.
        let point = MapGeometry.normalizedPoint(fromCanvasPoint: CGPoint(x: 1024, y: 512), manifest: manifest)
        #expect(abs(point.x - 0.5) < 0.0001)
        #expect(abs(point.y - 0.25) < 0.0001)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'MapViewport' in scope`

- [ ] **Step 3: Implémenter**

`NeonCompass/Core/Map/MapGeometry.swift` :
```swift
import CoreGraphics

/// État de zoom/pan de l'UIScrollView, poussé par TiledMapRepresentable
/// (Task 5) vers la couche SwiftUI pour positionner pins et overlays.
struct MapViewport: Equatable, Sendable {
    var zoomScale: CGFloat = 1
    var contentOffset: CGPoint = .zero
}

enum MapGeometry {
    static func fullSize(for manifest: TileManifest) -> CGFloat {
        CGFloat(manifest.tileSize * (1 << manifest.maxZoom))
    }

    static func screenPosition(for point: NormalizedPoint, manifest: TileManifest, viewport: MapViewport) -> CGPoint {
        let full = fullSize(for: manifest)
        return CGPoint(
            x: CGFloat(point.x) * full * viewport.zoomScale - viewport.contentOffset.x,
            y: CGFloat(point.y) * full * viewport.zoomScale - viewport.contentOffset.y
        )
    }

    /// `point` est en coordonnées du canvas UIKit plein-résolution (Task 5),
    /// pas du viewport visible — indépendant du zoom/pan courant.
    static func normalizedPoint(fromCanvasPoint point: CGPoint, manifest: TileManifest) -> NormalizedPoint {
        let full = fullSize(for: manifest)
        return NormalizedPoint(x: Double(point.x / full), y: Double(point.y / full))
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Map/MapGeometry.swift NeonCompassTests/Map/MapGeometryTests.swift
git commit -m "feat: MapGeometry normalized↔screen coordinate conversion"
```

---

### Task 5: `TiledMapView` — viewer UIKit wrappé (CATiledLayer)

**Files:**
- Create: `NeonCompass/Core/Map/TiledMapView.swift`

**Interfaces:**
- Consumes: `TileManifest` (Task 1), `MapViewport` (Task 4).
- Produces: `struct TiledMapRepresentable: UIViewRepresentable` (`init(manifest: TileManifest, viewport: Binding<MapViewport>, onLongPress: @escaping (CGPoint) -> Void)`) — `onLongPress` livre la position de l'appui long en coordonnées de la vue (espace plein-résolution, avant conversion normalisée), utilisée Task 9 pour la pose de pins personnels. Consommé par Task 9 (`MapScreen`).

Pas de test unitaire sur cette tâche : `CATiledLayer` et `UIScrollView` ne sont vérifiables qu'à l'exécution (build + rendu simulateur), comme la Task 4 du plan 1.

- [ ] **Step 1: Implémenter le viewer tuilé**

`NeonCompass/Core/Map/TiledMapView.swift` :
```swift
import SwiftUI
import UIKit

/// Seule pièce UIKit du moteur de carte — CATiledLayer n'a pas d'équivalent
/// SwiftUI. Toute la logique zoom/pan/tuiles est isolée ici (CLAUDE.md :
/// "UIKit seulement si une API l'impose, wrapped in one file").

/// Charge une tuile PNG pré-rendue depuis le folder reference bundlé (Task 1).
private enum TilePyramid {
    static func image(z: Int, x: Int, y: Int, bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: "\(y)", withExtension: "png", subdirectory: "MapTiles/\(z)/\(x)") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

/// Vue support de CATiledLayer. Le niveau de zoom courant se lit dans la CTM
/// du contexte au moment de draw(_:) — technique standard pour afficher une
/// pyramide de tuiles pré-rendues (cf. l'échantillon Apple "PhotoScroller").
private final class TiledCanvasView: UIView {
    override class var layerClass: AnyClass { CATiledLayer.self }

    private let manifest: TileManifest

    init(manifest: TileManifest) {
        self.manifest = manifest
        super.init(frame: .zero)
        let tiled = layer as! CATiledLayer
        tiled.tileSize = CGSize(width: manifest.tileSize, height: manifest.tileSize)
        tiled.levelsOfDetail = 1
        tiled.levelsOfDetailBias = manifest.maxZoom
        contentScaleFactor = 1
        isOpaque = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let scale = ctx.ctm.a
        guard scale > 0 else { return }
        let z = max(0, min(manifest.maxZoom, Int(round(log2(scale)))))
        let tileSizeInPoints = CGFloat(manifest.tileSize) / scale
        let x = Int(rect.origin.x / tileSizeInPoints)
        let y = Int(rect.origin.y / tileSizeInPoints)
        guard let image = TilePyramid.image(z: z, x: x, y: y) else { return }
        image.draw(in: rect)
    }
}

struct TiledMapRepresentable: UIViewRepresentable {
    let manifest: TileManifest
    @Binding var viewport: MapViewport
    let onLongPress: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: $viewport, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        let fullSize = MapGeometry.fullSize(for: manifest)
        let canvas = TiledCanvasView(manifest: manifest)
        canvas.frame = CGRect(x: 0, y: 0, width: fullSize, height: fullSize)
        scrollView.contentSize = canvas.frame.size
        scrollView.addSubview(canvas)
        scrollView.minimumZoomScale = 1 / CGFloat(1 << manifest.maxZoom)
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = scrollView.minimumZoomScale
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        context.coordinator.canvas = canvas

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        scrollView.addGestureRecognizer(longPress)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var canvas: UIView?
        @Binding private var viewport: MapViewport
        private let onLongPress: (CGPoint) -> Void

        init(viewport: Binding<MapViewport>, onLongPress: @escaping (CGPoint) -> Void) {
            _viewport = viewport
            self.onLongPress = onLongPress
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { sync(scrollView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { sync(scrollView) }

        private func sync(_ scrollView: UIScrollView) {
            viewport = MapViewport(zoomScale: scrollView.zoomScale, contentOffset: scrollView.contentOffset)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let canvas else { return }
            onLongPress(gesture.location(in: canvas))
        }
    }
}
```

- [ ] **Step 2: Vérifier que le projet build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **` (pas de test dédié — rendu vérifié visuellement à la Task 9)

- [ ] **Step 3: Commit**

```bash
git add NeonCompass/Core/Map/TiledMapView.swift
git commit -m "feat: TiledMapRepresentable — CATiledLayer zoom/pan viewer"
```

---

### Task 6: Overlay des pins POI + fiche POI Liquid Glass

**Files:**
- Create: `NeonCompass/Features/Map/MapPinsOverlay.swift`, `NeonCompass/Features/Map/POIDetailView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `POI`, `MapModel`, `MapGeometry`, `MapViewport`, `NCColor`, `NCTypography` (Tasks 2-4, Plan 1 Task 2).
- Produces: `struct MapPinsOverlay: View` (`init(pois: [POI], manifest: TileManifest, viewport: MapViewport, onTap: (POI) -> Void)`) ; `struct POIDetailView: View` (`init(poi: POI, isFound: Bool, onToggleFound: @escaping () -> Void, onDismiss: @escaping () -> Void)`). Consommé par Task 9.

Pas de test unitaire — vues SwiftUI pures, vérifiées par build + rendu visuel à la Task 9 (la logique testable sous-jacente — filtrage, found, géométrie — est déjà couverte aux Tasks 3-4).

- [ ] **Step 1: Implémenter l'overlay des pins**

`NeonCompass/Features/Map/MapPinsOverlay.swift` :
```swift
import SwiftUI

struct MapPinsOverlay: View {
    let pois: [POI]
    let manifest: TileManifest
    let viewport: MapViewport
    let onTap: (POI) -> Void

    var body: some View {
        ForEach(pois) { poi in
            let position = MapGeometry.screenPosition(for: poi.position, manifest: manifest, viewport: viewport)
            Button {
                onTap(poi)
            } label: {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(NCColor.neonCyan)
                    .shadow(color: NCColor.neonCyan.opacity(0.6), radius: 4)
            }
            .position(position)
            .accessibilityLabel(Text(poi.title.en))
        }
    }
}
```

- [ ] **Step 2: Implémenter la fiche POI**

`NeonCompass/Features/Map/POIDetailView.swift` :
```swift
import SwiftUI

struct POIDetailView: View {
    let poi: POI
    let isFound: Bool
    let onToggleFound: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(poi.title.en)
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if let note = poi.note {
                Text(note.en)
                    .font(NCTypography.body)
                    .foregroundStyle(.secondary)
            }

            Button {
                onToggleFound()
            } label: {
                Label(
                    isFound ? "poi.detail.found" : "poi.detail.markFound",
                    systemImage: isFound ? "checkmark.circle.fill" : "circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(isFound ? NCColor.neonCyan : NCColor.sunsetMagenta)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }
}
```

- [ ] **Step 3: Ajouter les strings au String Catalog**

Dans `NeonCompass/Resources/Localizable.xcstrings`, ajouter deux entrées suivant le même format que les entrées `tab.*` existantes :
- `poi.detail.markFound` = "Mark as found"
- `poi.detail.found` = "Found"

- [ ] **Step 4: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Map/MapPinsOverlay.swift NeonCompass/Features/Map/POIDetailView.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: POI pins overlay + Liquid Glass detail card"
```

---

### Task 7: Filtres par catégorie + recherche

**Files:**
- Create: `NeonCompass/Features/Map/MapFilterControls.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `MapModel`, `POICategory`, `NCColor` (Task 3, Task 2, Plan 1 Task 2).
- Produces: `struct MapFilterControls: View` (`init(model: MapModel)`) — grappe de boutons glass (spec §5 : « Contrôles flottants de la carte… `GlassEffectContainer` »). Consommé par Task 9.

Pas de test unitaire — le state qu'elle manipule (`activeCategories`, `searchQuery`) est déjà testé côté `MapModel` (Task 3).

- [ ] **Step 1: Implémenter les contrôles**

`NeonCompass/Features/Map/MapFilterControls.swift` :
```swift
import SwiftUI

struct MapFilterControls: View {
    @Bindable var model: MapModel
    @State private var showFilters = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .trailing, spacing: 12) {
                if showFilters {
                    categoryChips
                }
                HStack(spacing: 12) {
                    searchField
                    filterToggleButton
                }
            }
        }
        .padding(16)
    }

    private var filterToggleButton: some View {
        Button {
            withAnimation(.snappy) { showFilters.toggle() }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var searchField: some View {
        TextField("map.search.placeholder", text: $model.searchQuery)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)
    }

    private var categoryChips: some View {
        ForEach(POICategory.allCases, id: \.self) { category in
            let isActive = model.activeCategories.contains(category)
            Button {
                toggle(category)
            } label: {
                Text(category.rawValue)
                    .font(.caption)
                    .foregroundStyle(isActive ? NCColor.neonCyan : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func toggle(_ category: POICategory) {
        if model.activeCategories.contains(category) {
            model.activeCategories.remove(category)
        } else {
            model.activeCategories.insert(category)
        }
    }
}
```

- [ ] **Step 2: Ajouter la string du placeholder de recherche**

Dans `Localizable.xcstrings`, ajouter `map.search.placeholder` = "Search the map".

- [ ] **Step 3: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Map/MapFilterControls.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: map category filter chips + search field"
```

---

### Task 8: Pins personnels — pose par appui long + liste

**Files:**
- Create: `NeonCompass/Features/Map/PersonalPinsOverlay.swift`, `NeonCompass/Features/Map/PersonalPinListSheet.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `MapModel`, `PersonalPin`, `MapGeometry` (Task 3, Task 4).
- Produces: `struct PersonalPinsOverlay: View` (`init(pins: [PersonalPin], manifest: TileManifest, viewport: MapViewport)`) ; `struct PersonalPinListSheet: View` (`init(model: MapModel)`). Consommé par Task 9.

- [ ] **Step 1: Implémenter l'overlay des pins personnels**

`NeonCompass/Features/Map/PersonalPinsOverlay.swift` :
```swift
import SwiftUI

struct PersonalPinsOverlay: View {
    let pins: [PersonalPin]
    let manifest: TileManifest
    let viewport: MapViewport

    var body: some View {
        ForEach(pins) { pin in
            let point = NormalizedPoint(x: pin.x, y: pin.y)
            let position = MapGeometry.screenPosition(for: point, manifest: manifest, viewport: viewport)
            Image(systemName: "star.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(NCColor.sunsetOrange)
                .position(position)
                .accessibilityLabel(Text(pin.title))
        }
    }
}
```

- [ ] **Step 2: Implémenter la liste / suppression des pins personnels**

`NeonCompass/Features/Map/PersonalPinListSheet.swift` :
```swift
import SwiftUI

struct PersonalPinListSheet: View {
    @Bindable var model: MapModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.personalPins) { pin in
                    Text(pin.title)
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.deletePersonalPin(model.personalPins[index])
                    }
                }
            }
            .navigationTitle(Text("map.personalPins.title"))
        }
    }
}
```

- [ ] **Step 3: Ajouter les strings**

Dans `Localizable.xcstrings` : `map.personalPins.title` = "My pins", `map.personalPins.addPrompt` = "Name this pin", `map.personalPins.save` = "Save", `map.personalPins.cancel` = "Cancel".

- [ ] **Step 4: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Map/PersonalPinsOverlay.swift NeonCompass/Features/Map/PersonalPinListSheet.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: personal pins overlay + management list"
```

---

### Task 9: `MapScreen` — assemblage et intégration dans `RootView`

**Files:**
- Create: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/App/RootView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: tout ce qui précède (Tasks 1-8), `AppTab`, `AppModel`, `PlaceholderScreen` (Plan 1).
- Produces: `struct MapScreen: View` — remplace `PlaceholderScreen(tab: .map)` dans `RootView`.

Pas de test unitaire — assemblage de vues, vérifié par build + vérification visuelle simulateur iPhone **et** iPad (comme la Task 4 du plan 1).

- [ ] **Step 1: Implémenter `MapScreen`**

`NeonCompass/Features/Map/MapScreen.swift` :
```swift
import SwiftUI
import SwiftData

struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model: MapModel?
    @State private var viewport = MapViewport()
    @State private var showPersonalPinList = false
    @State private var pendingPinLocation: NormalizedPoint?
    @State private var pendingPinTitle = ""

    private let manifest = TileManifest.load() ?? TileManifest(tileSize: 256, maxZoom: 3, tileCount: 85)

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                ProgressView()
                    .task { loadModel() }
            }
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    @ViewBuilder
    private func content(model: MapModel) -> some View {
        if sizeClass == .compact {
            ZStack(alignment: .topTrailing) {
                mapCanvas(model: model)
                MapFilterControls(model: model)
            }
            .sheet(item: Binding(get: { model.selectedPOI }, set: { model.selectedPOI = $0 })) { poi in
                POIDetailView(
                    poi: poi,
                    isFound: model.isFound(poi),
                    onToggleFound: { model.toggleFound(poi) },
                    onDismiss: { model.selectedPOI = nil }
                )
                .presentationDetents([.medium])
            }
        } else {
            HStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    mapCanvas(model: model)
                    MapFilterControls(model: model)
                }
                if let selected = model.selectedPOI {
                    POIDetailView(
                        poi: selected,
                        isFound: model.isFound(selected),
                        onToggleFound: { model.toggleFound(selected) },
                        onDismiss: { model.selectedPOI = nil }
                    )
                    .frame(width: 340)
                    .transition(.move(edge: .trailing))
                }
            }
        }
    }

    private func mapCanvas(model: MapModel) -> some View {
        ZStack(alignment: .topLeading) {
            TiledMapRepresentable(manifest: manifest, viewport: $viewport) { canvasPoint in
                pendingPinLocation = MapGeometry.normalizedPoint(fromCanvasPoint: canvasPoint, manifest: manifest)
            }
            MapPinsOverlay(pois: model.filteredPOIs, manifest: manifest, viewport: viewport) { poi in
                model.selectedPOI = poi
            }
            PersonalPinsOverlay(pins: model.personalPins, manifest: manifest, viewport: viewport)

            Button {
                showPersonalPinList = true
            } label: {
                Image(systemName: "star.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(16)
        }
        .sheet(isPresented: $showPersonalPinList) {
            PersonalPinListSheet(model: model)
        }
        .alert(
            "map.personalPins.addPrompt",
            isPresented: Binding(get: { pendingPinLocation != nil }, set: { if !$0 { pendingPinLocation = nil } })
        ) {
            TextField("map.personalPins.addPrompt", text: $pendingPinTitle)
            Button("map.personalPins.save") {
                if let location = pendingPinLocation, !pendingPinTitle.isEmpty {
                    model.addPersonalPin(at: location, title: pendingPinTitle)
                }
                pendingPinTitle = ""
                pendingPinLocation = nil
            }
            Button("map.personalPins.cancel", role: .cancel) {
                pendingPinLocation = nil
                pendingPinTitle = ""
            }
        }
    }

    private func loadModel() {
        guard model == nil else { return }
        let pois = (try? POILoader.loadSeed()) ?? []
        model = MapModel(pois: pois, modelContext: modelContext)
    }
}
```

`TiledMapRepresentable` livre `canvasPoint` en coordonnées du canvas UIKit plein-résolution (Task 5, `onLongPress` callback) — converti directement via `MapGeometry.normalizedPoint(fromCanvasPoint:manifest:)`, sans dépendance au `viewport` courant (ce point est zoom/pan-indépendant par construction, cf. Task 4).

- [ ] **Step 2: Remplacer le placeholder dans `RootView`**

Dans `NeonCompass/App/RootView.swift`, remplacer les deux occurrences de `PlaceholderScreen(tab: model.selectedTab)` / `PlaceholderScreen(tab: tab)` par une fonction qui bascule sur `MapScreen` pour l'onglet carte :
```swift
    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        if tab == .map {
            MapScreen()
        } else {
            PlaceholderScreen(tab: tab)
        }
    }
```
et mettre à jour `compactLayout`/`regularLayout` pour appeler `screen(for: model.selectedTab)` / `screen(for: tab)` au lieu de `PlaceholderScreen(...)`.

- [ ] **Step 3: Build et vérification visuelle**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

Puis lancement simulateur (iPhone **et** iPad) : onglet Carte affiche l'artwork placeholder synthwave zoomable/déplaçable, 3 pins néon cyan visibles, tap sur un pin ouvre la fiche (sheet sur iPhone, panneau latéral sur iPad), bouton « Mark as found » bascule l'état et persiste après redémarrage de l'app, appui long sur la carte propose de nommer un pin personnel (icône étoile orange).

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Map/MapScreen.swift NeonCompass/App/RootView.swift NeonCompass/Core/Map/TiledMapView.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: wire MapScreen into RootView, replacing map placeholder"
```

---

## Self-Review

**Couverture spec/roadmap** : viewer tuilé CATiledLayer (Task 5) ✓, POI coordonnées normalisées (Task 2, 4) ✓, filtres/recherche (Task 7) ✓, fiche POI glass + « Trouvé » → SwiftData (Task 3, 6) ✓, pins perso (Task 8) ✓. La contribution communautaire (appui long → proposer un spot public, votes, blocage utilisateur) reste explicitement hors scope — c'est le plan 5 (Comptes & communauté), qui dépend de Sign in with Apple non encore implémenté.

**Cohérence des types** : `POI`/`POICategory`/`NormalizedPoint`/`LocalizedText` (Task 2) réutilisés tels quels dans `MapModel` (Task 3), `MapGeometry` (Task 4), `MapPinsOverlay`/`POIDetailView` (Task 6) — aucune redéfinition divergente. `TileManifest` (Task 1) consommé identiquement par `MapGeometry` (Task 4) et `TiledMapRepresentable` (Task 5). `MapViewport` défini une seule fois (Task 4), utilisé par Task 5, 6, 8, 9.
