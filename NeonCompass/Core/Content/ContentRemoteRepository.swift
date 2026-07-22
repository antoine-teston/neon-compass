import Foundation

/// Abstraction sur la source distante d'un type de contenu (Firestore en
/// production). Remplace les trois protocoles dupliqués
/// (POIRemoteRepository/CheatRemoteRepository/GuideRemoteRepository).
protocol ContentRemoteRepository<Item>: Sendable {
    associatedtype Item: Sendable
    func fetchAll() async throws -> [Item]
}
