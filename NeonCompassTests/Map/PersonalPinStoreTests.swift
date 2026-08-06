import Foundation
import SwiftData
import Testing
@testable import NeonCompass

@MainActor
struct PersonalPinStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self, PersonalPin.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - Icônes

    /// Une valeur brute inconnue vient d'un carnet écrit par une version plus
    /// récente (chantier 2, synchro). Une épingle mal illustrée reste une
    /// épingle ; une épingle qui refuse de se décoder disparaît.
    @Test func anUnknownIconFallsBackToTheMarker() {
        #expect(PersonalPinIcon.from(rawValue: "helicopter") == .marker)
        #expect(PersonalPinIcon.from(rawValue: "") == .marker)
    }

    /// Chaque icône porte un glyphe DISTINCT : c'est le glyphe qui distingue les
    /// épingles entre elles, puisqu'elles partagent toutes la même teinte.
    @Test func everyIconHasItsOwnSymbol() {
        let symbols = PersonalPinIcon.allCases.map(\.symbol)
        #expect(Set(symbols).count == PersonalPinIcon.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    /// Le défaut du modèle répare le bug de fuite entre cartes : une épingle
    /// écrite sans carte appartient à la carte de référence, celle sur laquelle
    /// l'app s'ouvre.
    @Test func aPinDefaultsToTheReferenceMap() {
        let pin = PersonalPin(x: 0.5, y: 0.5, title: "Planque")
        #expect(pin.game == Game.reference.rawValue)
        #expect(pin.iconValue == .marker)
        #expect(pin.isDone == false)
        #expect(pin.note.isEmpty)
        #expect(pin.deletedAt == nil)
    }

    // MARK: - Plafond

    /// Vingt en gratuit, toutes cartes confondues — un plafond PAR carte en
    /// vaudrait quarante et ne voudrait plus rien dire.
    @Test func theFreeCapBlocksTheTwentyFirstPin() {
        let store = PersonalPinStore(modelContext: makeContext())
        for index in 0..<PersonalPinStore.freeCap {
            let created = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false)
            #expect(created != nil, "la création \(index) aurait dû passer")
        }
        #expect(store.isAtCap(isProEntitled: false))
        #expect(store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false) == nil)
        #expect(store.pins.count == PersonalPinStore.freeCap)
    }

    /// Le plafond compte les DEUX cartes : quinze ici plus cinq là doivent buter.
    @Test func theCapCountsEveryMapTogether() {
        let store = PersonalPinStore(modelContext: makeContext())
        for _ in 0..<15 { store.create(at: NormalizedPoint(x: 0.1, y: 0.1), game: .reference, isProEntitled: false) }
        for _ in 0..<5 { store.create(at: NormalizedPoint(x: 0.2, y: 0.2), game: .leonida, isProEntitled: false) }
        #expect(store.create(at: NormalizedPoint(x: 0.3, y: 0.3), game: .leonida, isProEntitled: false) == nil)
    }

    @Test func proHasNoCap() {
        let store = PersonalPinStore(modelContext: makeContext())
        for _ in 0..<(PersonalPinStore.freeCap + 5) {
            store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)
        }
        #expect(store.pins.count == PersonalPinStore.freeCap + 5)
        #expect(store.isAtCap(isProEntitled: true) == false)
    }

    /// Règle de déclassement : on ne supprime JAMAIS. Un carnet au-dessus du
    /// plafond reste entièrement modifiable — seul l'ajout est fermé.
    @Test func anOverCapNotebookStaysEditable() {
        let store = PersonalPinStore(modelContext: makeContext())
        for _ in 0..<25 { store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true) }
        let pin = store.pins[0]
        store.update(pin, title: "Renommée", note: "Toujours modifiable")
        store.toggleDone(pin)
        #expect(pin.title == "Renommée")
        #expect(pin.isDone)
        store.delete(pin)
        #expect(store.pins.count == 24)
    }

    // MARK: - Portée par carte

    /// Le bug que ce chantier répare : une épingle ne doit apparaître que sur la
    /// carte où elle a été posée.
    @Test func aPinBelongsToExactlyOneMap() {
        let store = PersonalPinStore(modelContext: makeContext())
        store.create(at: NormalizedPoint(x: 0.1, y: 0.1), game: .reference, isProEntitled: true)
        store.create(at: NormalizedPoint(x: 0.2, y: 0.2), game: .leonida, isProEntitled: true)
        #expect(store.pins(for: .reference).count == 1)
        #expect(store.pins(for: .leonida).count == 1)
        #expect(store.pins(for: .reference)[0].gameValue == .reference)
    }

    // MARK: - Générations

    /// Sans génération qui avance, le moteur de carte ne repousse pas son
    /// contenu et l'épingle posée n'apparaît jamais.
    @Test func creatingDeletingAndTogglingAdvanceTheGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        var seen: Set<Int> = [store.generation]
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        #expect(seen.insert(store.generation).inserted, "la création n'a pas avancé la génération")
        store.toggleDone(pin)
        #expect(seen.insert(store.generation).inserted, "la coche n'a pas avancé la génération")
        store.setIcon(.vehicle, on: pin)
        #expect(seen.insert(store.generation).inserted, "l'icône n'a pas avancé la génération")
        store.delete(pin)
        #expect(seen.insert(store.generation).inserted, "la suppression n'a pas avancé la génération")
    }

    /// Le titre et la note ne changent PAS le dessin de l'épingle : les commettre
    /// ne doit pas périmer le contenu du moteur, sans quoi chaque session
    /// d'édition ferait rebâtir toutes les pastilles de la carte.
    @Test func editingTextDoesNotAdvanceTheGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        let before = store.generation
        store.update(pin, title: "Un nom", note: "Une note")
        #expect(store.generation == before)
    }

    // MARK: - updatedAt

    @Test func editingMovesUpdatedAtOnlyWhenSomethingChanged() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        pin.updatedAt = .distantPast
        store.update(pin, title: "", note: "")   // rien n'a changé : le titre était déjà vide
        #expect(pin.updatedAt == .distantPast, "une édition sans changement ne doit pas dater l'épingle")
        store.update(pin, title: "Un nom", note: "")
        #expect(pin.updatedAt > .distantPast)
    }

    /// Le magasin relit le disque, comme `FoundStore.refresh` : les tests et les
    /// chemins d'amorçage insèrent parfois par-derrière.
    @Test func refreshSeesWritesMadeBehindTheStore() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        context.insert(PersonalPin(x: 0.4, y: 0.4, game: .reference, title: "Par-derrière"))
        try? context.save()
        #expect(store.pins.isEmpty)
        store.refresh()
        #expect(store.pins.count == 1)
    }

    // MARK: - Pierre tombale

    /// La bascule du chantier 2 : supprimer n'efface plus, ça DATE. Sans la
    /// tombe, effacer sur l'iPhone ne se propagerait jamais — l'iPad possède
    /// encore l'épingle et rien ne lui dirait qu'elle a été retirée.
    @Test func deletingLeavesATombstoneBehind() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.delete(pin)
        #expect(store.pins.isEmpty, "une épingle supprimée ne doit plus être visible")
        let all = (try? context.fetch(FetchDescriptor<PersonalPin>())) ?? []
        #expect(all.count == 1, "la ligne doit subsister")
        #expect(all[0].deletedAt != nil, "elle doit porter sa date de suppression")
    }

    /// Une tombe ne se compte pas dans le plafond : sinon supprimer une épingle
    /// ne libèrerait jamais la place qu'elle occupait, et le carnet gratuit se
    /// remplirait une fois pour toutes.
    @Test func tombstonesDoNotCountTowardTheCap() {
        let store = PersonalPinStore(modelContext: makeContext())
        for _ in 0..<PersonalPinStore.freeCap {
            store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false)
        }
        #expect(store.isAtCap(isProEntitled: false))
        store.delete(store.pins[0])
        #expect(!store.isAtCap(isProEntitled: false), "supprimer doit libérer une place")
        #expect(store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false) != nil)
    }

    /// Et une tombe ne réapparaît pas non plus sur la carte.
    @Test func tombstonesAreInvisibleToTheMap() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.delete(pin)
        #expect(store.pins(for: .reference).isEmpty)
    }

    /// Ni après relecture du disque : le filtre vit dans `refresh`, en un seul
    /// endroit, et c'est ce qui garantit qu'aucun chemin ne peut l'oublier.
    @Test func tombstonesStayHiddenAcrossARefresh() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.delete(pin)
        store.refresh()
        #expect(store.pins.isEmpty)
        // Et le magasin reconstruit sur le même contexte ne les voit pas non plus.
        let reopened = PersonalPinStore(modelContext: context)
        #expect(reopened.pins.isEmpty)
    }

    // MARK: - Sélection

    /// Le panneau tient une référence à l'épingle sélectionnée. La supprimer sans
    /// vider la sélection laisserait le panneau sur un objet effacé.
    @Test func deletingTheSelectedPinClearsTheSelection() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let model = MapModel(pois: [], modelContext: context)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        model.selection = .pin(pin)
        #expect(model.selection?.pin === pin)
        model.clearSelectionIfPin(pin)
        #expect(model.selection == nil)
    }

    /// Le commit de fin d'édition ne doit RIEN ressusciter.
    ///
    /// Le chemin réel : supprimer depuis la fiche retire celle-ci de l'arbre,
    /// `onDisappear` tire `commit`, et `commit` écrivait sur une instance
    /// invalidée. La fiche s'en garde par son drapeau `isDeleting` ; ce test
    /// vérifie l'autre moitié du contrat — que le magasin, lui, ne fait pas
    /// réapparaître ce qu'il vient d'effacer.
    @Test func writingAfterADeleteDoesNotResurrectThePin() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.delete(pin)
        #expect(store.pins.isEmpty)
        store.refresh()
        #expect(store.pins.isEmpty, "l'épingle est revenue après relecture du disque")
    }

    /// La somme interdit l'état impossible : deux natures ne peuvent pas être
    /// sélectionnées en même temps, ce que deux `Optional` côte à côte auraient
    /// laissé exprimer.
    @Test func selectingAPOIReplacesASelectedPin() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let model = MapModel(pois: [], modelContext: context)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        model.selection = .pin(pin)
        let poi = POI(id: "a", category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
                      title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil)
        model.selection = .poi(poi)
        #expect(model.selection?.pin == nil)
        #expect(model.selection?.poi?.id == "a")
    }
}
