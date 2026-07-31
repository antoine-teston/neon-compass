import SwiftData
import Testing
@testable import NeonCompass

/// Le moteur de carte ne repousse son contenu que si le jeton a changé. Un
/// changement qui n'atteindrait pas le jeton ne serait pas une lenteur : ce
/// serait une carte qui MENT — un point ajouté qui n'apparaît pas, une épingle
/// supprimée qui reste. Ces tests portent donc sur les compteurs qui alimentent
/// ce jeton, pas sur le jeton lui-même (dont l'égalité est synthétisée).
@MainActor
struct MapContentTokenTests {
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

    // MARK: - Épingles personnelles

    /// Le cas qui a motivé ce compteur : sans lui, poser une épingle ne
    /// changerait rien de comparable et la carte ne la dessinerait jamais.
    @Test func addingAPersonalPinAdvancesItsGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let before = model.personalPinsGeneration
        model.addPersonalPin(at: NormalizedPoint(x: 0.5, y: 0.5), title: "Planque")
        #expect(model.personalPinsGeneration != before)
        #expect(model.personalPins.count == 1)
    }

    /// Supprimer compte autant qu'ajouter : une épingle retirée doit disparaître.
    @Test func deletingAPersonalPinAdvancesItsGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        model.addPersonalPin(at: NormalizedPoint(x: 0.5, y: 0.5), title: "Planque")
        let before = model.personalPinsGeneration
        model.deletePersonalPin(model.personalPins[0])
        #expect(model.personalPinsGeneration != before)
        #expect(model.personalPins.isEmpty)
    }

    /// Deux épingles successives doivent donner deux générations distinctes —
    /// un compteur qui se contenterait de basculer entre deux valeurs
    /// retomberait sur la précédente une fois sur deux.
    @Test func successivePersonalPinsNeverRepeatAGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        var seen: Set<Int> = [model.personalPinsGeneration]
        for index in 0..<5 {
            model.addPersonalPin(at: NormalizedPoint(x: 0.1 * Double(index), y: 0.5), title: "P\(index)")
            #expect(seen.insert(model.personalPinsGeneration).inserted, "génération déjà vue au tour \(index)")
        }
    }

    // MARK: - Points d'intérêt

    /// L'état « trouvé » se rend DANS la pastille (une coche remplace le
    /// glyphe). Il doit donc atteindre le jeton, sans quoi cocher un lieu
    /// depuis sa fiche ne changerait rien à l'écran.
    @Test func togglingFoundAdvancesThePOIGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let before = model.poisGeneration
        model.toggleFound(samplePOIs()[0])
        #expect(model.poisGeneration != before)
    }

    /// Filtrer change la liste dessinée.
    @Test func filteringAdvancesThePOIGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let before = model.poisGeneration
        model.activeCategories = [.landmark]
        #expect(model.poisGeneration != before)
    }

    /// Et l'arrivée du contenu distant aussi — c'est le chemin par lequel les
    /// vrais points remplacent le socle embarqué.
    @Test func updatingPOIsAdvancesTheGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let before = model.poisGeneration
        model.updatePOIs(samplePOIs() + [
            POI(id: "c", category: .vehicle, position: NormalizedPoint(x: 0.9, y: 0.9),
                title: LocalizedText(en: "Gamma", fr: nil, es: nil, it: nil, de: nil), note: nil),
        ])
        #expect(model.poisGeneration != before)
        #expect(model.filteredPOIs.count == 3)
    }

    // MARK: - Ce que le jeton doit distinguer

    /// La sélection d'une fiche, elle, ne doit RIEN changer au contenu de la
    /// carte : c'est exactement ce que le court-circuit exploite. Si un jour
    /// une fiche ouverte modifiait le rendu d'une pastille, il faudrait
    /// l'ajouter au jeton — ce test le rappellerait.
    @Test func selectingAPOIChangesNoGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let pois = model.poisGeneration
        let pins = model.personalPinsGeneration
        model.selectedPOI = model.filteredPOIs[0]
        model.selectedPOI = nil
        #expect(model.poisGeneration == pois)
        #expect(model.personalPinsGeneration == pins)
    }
}
