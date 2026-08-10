import Foundation
import Testing
@testable import NeonCompass

/// Le jeu actif de l'écran Codes, depuis qu'il a quitté `CheatsModel`.
///
/// Ces deux assertions vivaient dans `CheatsModelTests` — elles y sont mortes
/// avec le déménagement, la bascule étant passée dans la barre haute et son état
/// dans `AppModel`. Elles sont déplacées et non réécrites : ce qu'elles
/// garantissent n'a pas changé de nature, seulement d'adresse.
@MainActor
struct AppModelGameTests {
    private func defaults(_ name: String) -> UserDefaults {
        let store = UserDefaults(suiteName: "AppModelGameTests.\(name)")!
        store.removePersistentDomain(forName: "AppModelGameTests.\(name)")
        return store
    }

    /// Ouvrir sur le jeu à venir afficherait un écran d'attente au premier
    /// lancement : c'est celui qui a des codes qui accueille.
    @Test func premierLancementSurLeJeuQuiADesCodes() {
        #expect(AppModel(defaults: defaults(#function)).activeGame == .reference)
    }

    @Test func retientLeJeuChoisi() {
        let store = defaults(#function)
        AppModel(defaults: store).activeGame = .leonida
        #expect(AppModel(defaults: store).activeGame == .leonida)
    }

    /// La clé de persistance porte encore le nom de l'endroit d'où l'état vient.
    /// La renommer renverrait au défaut tous ceux qui avaient déjà choisi — ce
    /// test est ce qui empêche un « rangement » bien intentionné de le faire.
    @Test func laCleHeriteeEstCelleQuiEstLue() {
        let store = defaults(#function)
        store.set(Game.leonida.rawValue, forKey: "cheatsActiveGame")
        #expect(AppModel(defaults: store).activeGame == .leonida)
    }
}
