import Foundation

/// Abstraction sur la source distante des cheats (Firestore en production).
protocol CheatRemoteRepository: Sendable {
    func fetchAll() async throws -> [Cheat]
}
