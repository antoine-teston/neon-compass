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

    private func text(_ value: String) -> LocalizedText {
        LocalizedText(en: value, fr: nil, es: nil, it: nil, de: nil)
    }

    /// Trois POI d'une collection dont le total attendu est 3 : la progression
    /// se lit donc directement en tiers.
    private func samplePOIs() -> [POI] {
        [
            POI(id: "a", category: .landmark, collection: "marks", position: NormalizedPoint(x: 0.1, y: 0.1),
                title: text("Alpha")),
            POI(id: "b", category: .landmark, collection: "marks", position: NormalizedPoint(x: 0.2, y: 0.2),
                title: text("Beta")),
            POI(id: "c", category: .collectible, collection: "marks", position: NormalizedPoint(x: 0.3, y: 0.3),
                title: text("Gamma")),
        ]
    }

    private func sampleCollections() -> [POICollection] {
        [POICollection(id: "marks", game: .reference, title: text("Marks"), isChallenge: true, expectedCount: 3)]
    }

    private func sampleTrophy(id: String) -> Trophy {
        Trophy(id: id, title: text("Trophy \(id)"), note: nil)
    }

    private func makeModel(
        pois: [POI] = [],
        collections: [POICollection]? = nil,
        trophies: [Trophy] = [],
        context: ModelContext
    ) -> ProgressionModel {
        ProgressionModel(
            pois: pois,
            collections: collections ?? sampleCollections(),
            trophies: trophies,
            modelContext: context
        )
    }

    @Test func overallProgressReflectsFoundEntries() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let model = makeModel(pois: samplePOIs(), context: context)
        #expect(abs(model.overallProgress - (1.0 / 3.0)) < 0.0001)
    }

    @Test func overallProgressIsZeroWithNoPOIs() {
        #expect(makeModel(context: makeContext()).overallProgress == 0)
    }

    @Test func overallProgressIsZeroWhenNoCollectionIsDeclared() {
        // Le dénominateur est éditorial : sans collection déclarée il n'y a
        // aucun défi, donc rien à afficher — surtout pas un ratio dérivé du
        // nombre de POI qu'on a chargés.
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let model = makeModel(pois: samplePOIs(), collections: [], context: context)
        #expect(model.challenges.isEmpty)
        #expect(model.overallProgress == 0)
    }

    @Test func challengesAreScopedToTheirGame() {
        let collections = [
            POICollection(id: "marks", game: .reference, title: text("Marks"), isChallenge: true, expectedCount: 3),
            POICollection(id: "leo", game: .leonida, title: text("Leo"), isChallenge: true, expectedCount: 5),
        ]
        let model = makeModel(pois: samplePOIs(), collections: collections, context: makeContext())
        #expect(model.challenges(for: .reference).map(\.id) == ["marks"])
        #expect(model.challenges(for: .leonida).map(\.id) == ["leo"])
        #expect(model.gamesWithChallenges == [.leonida, .reference])
    }

    @Test func widgetProgressPrefersTheUpcomingGameOnceItHasAKnownTotal() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        context.insert(FoundEntry(poiID: "leo1"))
        let collections = [
            POICollection(id: "marks", game: .reference, title: text("Marks"), isChallenge: true, expectedCount: 3),
            POICollection(id: "leo", game: .leonida, title: text("Leo"), isChallenge: true, expectedCount: 4),
        ]
        let pois = samplePOIs() + [
            POI(id: "leo1", category: .collectible, collection: "leo", position: nil, title: text("Leo 1")),
        ]
        let model = makeModel(pois: pois, collections: collections, context: context)
        #expect(abs(model.overallProgress - 0.25) < 0.0001)
    }

    @Test func widgetProgressFallsBackToTheReferenceGame() {
        // Tant que le volet à venir n'a aucun total connu, le chiffre unique du
        // widget vient de la carte de référence — la seule à en avoir.
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let collections = sampleCollections() + [
            POICollection(id: "leo", game: .leonida, title: text("Leo"), isChallenge: true),
        ]
        let model = makeModel(pois: samplePOIs(), collections: collections, context: context)
        #expect(abs(model.overallProgress - (1.0 / 3.0)) < 0.0001)
        #expect(model.overallProgress(for: .leonida) == nil)
    }

    @Test func toggleTrophyPersistsAndIsIdempotent() {
        let trophy = sampleTrophy(id: "t1")
        let model = makeModel(trophies: [trophy], context: makeContext())
        #expect(!model.isTrophyChecked(trophy))
        model.toggleTrophy(trophy)
        #expect(model.isTrophyChecked(trophy))
        model.toggleTrophy(trophy)
        #expect(!model.isTrophyChecked(trophy))
    }

    @Test func refreshFoundStatePicksUpEntriesInsertedAfterConstruction() {
        let context = makeContext()
        let model = makeModel(pois: samplePOIs(), context: context)
        #expect(model.overallProgress == 0)

        context.insert(FoundEntry(poiID: "a"))
        try? context.save()

        // Without a refresh, the model's snapshot is stale.
        #expect(model.overallProgress == 0)

        model.refreshFoundState()
        #expect(abs(model.overallProgress - (1.0 / 3.0)) < 0.0001)
    }

    @Test func updatePOIsAndUpdateTrophiesReplaceContent() {
        let model = makeModel(context: makeContext())
        model.updatePOIs(samplePOIs())
        model.updateTrophies([sampleTrophy(id: "t1")])
        #expect(model.pois.map(\.id) == ["a", "b", "c"])
        #expect(model.trophies.map(\.id) == ["t1"])
    }

    @Test func updatePOIsRecomputesChallenges() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let model = makeModel(context: context)
        #expect(model.challenges.first?.referenced == 0)

        model.updatePOIs(samplePOIs())
        #expect(model.challenges.first?.referenced == 3)
        #expect(model.challenges.first?.found == 1)
    }
}
