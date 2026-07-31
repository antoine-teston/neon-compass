import Foundation

/// Abstraction sur Remote Config — permet de tester le versionnement de
/// contenu sans dépendre du SDK Firebase (spec §3 : "Firebase isolé derrière
/// des protocoles dans Core/").
protocol ContentVersionProviding: Sendable {
    func currentVersion() async throws -> Int

    /// Jette ce que le fournisseur garde en mémoire, pour que le prochain
    /// `currentVersion()` reparte de la source. Appelé sur un rafraîchissement
    /// demandé par l'utilisateur, et seulement là.
    ///
    /// Sans opération par défaut : un fournisseur qui ne met rien en cache n'a
    /// rien à jeter, et ne devrait pas avoir à le déclarer.
    func invalidate() async
}

extension ContentVersionProviding {
    func invalidate() async {}
}
