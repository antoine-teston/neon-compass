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

    @Test func filteredPOIsExcludesPositionPendingPOIs() {
        let pending = POI(id: "c", category: .landmark, position: nil,
                           title: LocalizedText(en: "Pending", fr: nil, es: nil, it: nil, de: nil), note: nil)
        let model = MapModel(pois: samplePOIs() + [pending], modelContext: makeContext())
        #expect(model.filteredPOIs.map(\.id) == ["a", "b"])
        #expect(model.pois.map(\.id) == ["a", "b", "c"])
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

    @Test func foundPOIIDsReflectsToggleImmediately() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let poi = samplePOIs()[0]
        #expect(!model.foundPOIIDs.contains(poi.id))
        model.toggleFound(poi)
        #expect(model.foundPOIIDs.contains(poi.id))
        model.toggleFound(poi)
        #expect(!model.foundPOIIDs.contains(poi.id))
    }

    @Test func referenceMapUsesBundledFixture() {
        let remote = [makePOI(id: "poi_remote", position: nil)]
        let fixture = [makePOI(id: "poi_fixture", position: NormalizedPoint(x: 0.5, y: 0.5))]
        #expect(MapModel.pois(for: .reference, remote: remote, reference: fixture).map(\.id) == ["poi_fixture"])
    }

    // Invariant de correction, pas de confort : les positions de la fixture
    // sont normalisées sur la carte de référence. Un repli vers elle quand le
    // contenu distant est vide poserait plus de mille pins n'importe où sur le
    // placeholder. Une carte `leonida` sans contenu DOIT rester vide.
    @Test func leonidaMapNeverFallsBackToFixture() {
        let fixture = [makePOI(id: "poi_fixture", position: NormalizedPoint(x: 0.5, y: 0.5))]
        #expect(MapModel.pois(for: .leonida, remote: [], reference: fixture).isEmpty)
        let unplaceable = [makePOI(id: "poi_remote", position: nil)]
        #expect(MapModel.pois(for: .leonida, remote: unplaceable, reference: fixture).map(\.id) == ["poi_remote"])
    }

    /// La fixture ne doit pas être décodée quand on affiche l'autre carte —
    /// le parse JSON coûte ~200 Ko pour rien.
    @Test func fixtureIsNotDecodedForLeonidaMap() {
        final class Flag: @unchecked Sendable { var evaluated = false }
        let flag = Flag()
        _ = MapModel.pois(for: .leonida, remote: [], reference: { flag.evaluated = true; return [] }())
        #expect(!flag.evaluated)
    }

    private func makePOI(id: String, position: NormalizedPoint?) -> POI {
        POI(id: id, category: .landmark, position: position,
            title: LocalizedText(en: "T", fr: nil, es: nil, it: nil, de: nil), note: nil)
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
