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
