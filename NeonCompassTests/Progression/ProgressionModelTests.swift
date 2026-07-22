import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct ProgressionModelTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self, TrophyProgress.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func samplePOIs() -> [POI] {
        [
            POI(id: "a", category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
                title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil),
            POI(id: "b", category: .landmark, position: NormalizedPoint(x: 0.2, y: 0.2),
                title: LocalizedText(en: "Beta", fr: nil, es: nil, it: nil, de: nil), note: nil),
            POI(id: "c", category: .collectible, position: NormalizedPoint(x: 0.3, y: 0.3),
                title: LocalizedText(en: "Gamma", fr: nil, es: nil, it: nil, de: nil), note: nil),
        ]
    }

    private func sampleTrophy(id: String) -> Trophy {
        Trophy(id: id, title: LocalizedText(en: "Trophy \(id)", fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func overallProgressReflectsFoundEntries() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let model = ProgressionModel(pois: samplePOIs(), trophies: [], modelContext: context)
        #expect(abs(model.overallProgress - (1.0 / 3.0)) < 0.0001)
    }

    @Test func overallProgressIsZeroWithNoPOIs() {
        let model = ProgressionModel(pois: [], trophies: [], modelContext: makeContext())
        #expect(model.overallProgress == 0)
    }

    @Test func progressInCategoryIsScopedToThatCategory() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let model = ProgressionModel(pois: samplePOIs(), trophies: [], modelContext: context)
        #expect(abs(model.progress(in: .landmark) - 0.5) < 0.0001)
        #expect(model.progress(in: .collectible) == 0)
    }

    @Test func toggleTrophyPersistsAndIsIdempotent() {
        let trophy = sampleTrophy(id: "t1")
        let model = ProgressionModel(pois: [], trophies: [trophy], modelContext: makeContext())
        #expect(!model.isTrophyChecked(trophy))
        model.toggleTrophy(trophy)
        #expect(model.isTrophyChecked(trophy))
        model.toggleTrophy(trophy)
        #expect(!model.isTrophyChecked(trophy))
    }

    @Test func refreshFoundStatePicksUpEntriesInsertedAfterConstruction() {
        let context = makeContext()
        let model = ProgressionModel(pois: samplePOIs(), trophies: [], modelContext: context)
        #expect(model.overallProgress == 0)

        context.insert(FoundEntry(poiID: "a"))
        try? context.save()

        // Without a refresh, the model's snapshot is stale.
        #expect(model.overallProgress == 0)

        model.refreshFoundState()
        #expect(abs(model.overallProgress - (1.0 / 3.0)) < 0.0001)
    }

    @Test func updatePOIsAndUpdateTrophiesReplaceContent() {
        let model = ProgressionModel(pois: [], trophies: [], modelContext: makeContext())
        model.updatePOIs(samplePOIs())
        model.updateTrophies([sampleTrophy(id: "t1")])
        #expect(model.pois.map(\.id) == ["a", "b", "c"])
        #expect(model.trophies.map(\.id) == ["t1"])
    }
}
