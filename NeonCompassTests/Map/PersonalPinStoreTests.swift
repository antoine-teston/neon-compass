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
}
