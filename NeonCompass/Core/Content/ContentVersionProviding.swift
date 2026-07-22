import Foundation

/// Abstraction sur Remote Config — permet de tester le versionnement de
/// contenu sans dépendre du SDK Firebase (spec §3 : "Firebase isolé derrière
/// des protocoles dans Core/").
protocol ContentVersionProviding: Sendable {
    func currentVersion() async throws -> Int
}
