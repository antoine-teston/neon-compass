import SwiftData
import Testing
@testable import NeonCompass

/// Le défaut que ces tests verrouillent : `MapModel` et `ProgressionModel`
/// tenaient chacun son cache des `FoundEntry`, et rien ne les reliait. Cocher des
/// lieux sur la carte laissait la progression sur une photographie périmée — sur
/// iPhone, jusqu'au lancement suivant, parce que l'unique relecture était accrochée
/// à un `.onAppear` qui ne se rejoue jamais dans un onglet resté monté.
@MainActor
struct FoundStoreTests {
    private func makeContext() -> ModelContext {
        let container = try! ModelContainer(
            for: FoundEntry.self, PersonalPin.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Trois POI d'une même collection dont le total attendu est 3 : la
    /// progression se lit donc directement en tiers.
    private func samplePOIs() -> [POI] {
        ["a", "b", "c"].map { id in
            POI(id: id, category: .collectible, collection: "marks",
                position: NormalizedPoint(x: 0.5, y: 0.5),
                title: LocalizedText(en: id, fr: nil, es: nil, it: nil, de: nil))
        }
    }

    private func sampleCollection() -> POICollection {
        POICollection(
            id: "marks", game: .reference,
            title: LocalizedText(en: "Marks", fr: nil, es: nil, it: nil, de: nil),
            isChallenge: true, expectedCount: 3
        )
    }

    // MARK: - Le magasin lui-même

    @Test func togglingReportsTheNewStateAndPersistsIt() {
        let context = makeContext()
        let store = FoundStore(modelContext: context)
        #expect(store.toggle("a", at: .now) == true)
        #expect(store.isFound("a"))
        // Relire le disque doit donner la même chose que le cache — sinon le
        // cache mentirait au prochain lancement.
        #expect(FoundStore(modelContext: context).isFound("a"))

        #expect(store.toggle("a", at: .now) == false)
        #expect(!store.isFound("a"))
        #expect(!FoundStore(modelContext: context).isFound("a"))
    }

    /// Le cas que `refresh()` existe pour couvrir : une écriture faite derrière le
    /// dos du magasin (chemin d'amorçage du widget, tests).
    @Test func refreshPicksUpWritesMadeBehindItsBack() {
        let context = makeContext()
        let store = FoundStore(modelContext: context)
        context.insert(FoundEntry(poiID: "a"))
        try? context.save()
        #expect(!store.isFound("a"))
        store.refresh()
        #expect(store.isFound("a"))
    }

    // MARK: - Ce que le partage referme

    /// L'invariant central. Aucune relecture, aucun rafraîchissement : ce que la
    /// carte écrit, la progression le voit DÉJÀ. C'est ce qui était faux avec deux
    /// caches, et ce qui rend possible le `onChange` de `DiscoverySection`.
    @Test func aMapWriteIsImmediatelyVisibleToProgression() {
        let context = makeContext()
        let store = FoundStore(modelContext: context)
        let map = MapModel(pois: samplePOIs(), modelContext: context, found: store)
        let progression = ProgressionModel(
            poisByGame: [.reference: samplePOIs()], collections: [],
            modelContext: context, found: store
        )

        #expect(progression.foundPOIIDs.isEmpty)
        map.toggleFound(samplePOIs()[0])
        #expect(progression.foundPOIIDs == ["a"])
        // Et dans l'autre sens, pour que décocher ne laisse pas de fantôme.
        map.toggleFound(samplePOIs()[0])
        #expect(progression.foundPOIIDs.isEmpty)
    }

    /// Le pendant côté défis : les compteurs dérivés doivent suivre dès qu'on leur
    /// demande de recalculer, sans avoir à reconstruire le modèle. C'est
    /// exactement l'enchaînement que déclenche `onChange` en production.
    @Test func recomputingAfterAMapWriteUpdatesTheChallengeCounts() {
        let context = makeContext()
        let store = FoundStore(modelContext: context)
        let map = MapModel(pois: samplePOIs(), modelContext: context, found: store)
        let progression = ProgressionModel(
            poisByGame: [.reference: samplePOIs()], collections: [sampleCollection()],
            modelContext: context, found: store
        )
        #expect(progression.overallProgress(for: .reference) == 0)

        map.toggleFound(samplePOIs()[0])
        progression.refreshFoundState()
        let progress = progression.overallProgress(for: .reference)
        #expect(progress != nil)
        #expect(abs((progress ?? 0) - (1.0 / 3.0)) < 0.0001)
    }

    /// Un magasin par défaut reste isolé — c'est ce qui laisse chaque test vivre
    /// sur son propre contexte, et ce qui garantit qu'on n'a pas troqué la
    /// divergence contre un singleton.
    @Test func modelsBuiltWithoutAStoreDoNotShareOne() {
        let context = makeContext()
        let first = MapModel(pois: samplePOIs(), modelContext: context)
        let second = MapModel(pois: samplePOIs(), modelContext: context)
        first.toggleFound(samplePOIs()[0])
        #expect(first.foundPOIIDs == ["a"])
        #expect(second.foundPOIIDs.isEmpty)
    }
}
