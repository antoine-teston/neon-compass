import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct ProgressionModelTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self])
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

    /// Les POI de test sont rangés sous la carte de référence par défaut :
    /// `samplePOIs()` ne porte que des collections `.reference`. Les cas qui
    /// veulent du volet à venir passent leur propre dictionnaire.
    private func makeModel(
        pois: [POI] = [],
        poisByGame: [Game: [POI]]? = nil,
        collections: [POICollection]? = nil,
        context: ModelContext
    ) -> ProgressionModel {
        ProgressionModel(
            poisByGame: poisByGame ?? [.reference: pois],
            collections: collections ?? sampleCollections(),
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

    @Test func updatePOIsReplacesContent() {
        let model = makeModel(context: makeContext())
        model.updatePOIs([.reference: samplePOIs()])
        #expect(model.pois.map(\.id) == ["a", "b", "c"])
    }

    /// LE test que le tableau fusionné faisait échouer. Un POI du volet à venir
    /// a `collection: nil` par défaut, donc il ne se rattache à AUCUN défi :
    /// compter par défi rendait le volet éternellement à zéro alors que ses POI
    /// se cochent déjà sur la carte. Le compte doit venir des POI du jeu.
    @Test func foundCountPerGameComesFromThePOIsNotTheChallenges() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        context.insert(FoundEntry(poiID: "leo1"))
        context.insert(FoundEntry(poiID: "leo2"))
        let uncharted = [
            POI(id: "leo1", category: .landmark, collection: nil, position: nil, title: text("Leo 1")),
            POI(id: "leo2", category: .landmark, collection: nil, position: nil, title: text("Leo 2")),
        ]
        let model = makeModel(
            poisByGame: [.leonida: uncharted, .reference: samplePOIs()],
            context: context
        )
        #expect(model.challenges(for: .leonida).isEmpty)
        #expect(model.foundCount(for: .leonida) == 2)
        #expect(model.foundCount(for: .reference) == 1)
    }

    /// L'aplatissement suit l'ordre de `Game` — le volet à venir d'abord — et pas
    /// celui du dictionnaire, qui n'en a pas.
    @Test func poisAreFlattenedInGameOrder() {
        let model = makeModel(
            poisByGame: [
                .reference: samplePOIs(),
                .leonida: [POI(id: "leo1", category: .landmark, collection: nil, position: nil, title: text("Leo 1"))],
            ],
            context: makeContext()
        )
        #expect(model.pois.map(\.id) == ["leo1", "a", "b", "c"])
    }

    @Test func updatePOIsRecomputesChallenges() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let model = makeModel(context: context)
        #expect(model.challenges.first?.referenced == 0)

        model.updatePOIs([.reference: samplePOIs()])
        #expect(model.challenges.first?.referenced == 3)
        #expect(model.challenges.first?.found == 1)
    }
}
