import Foundation

/// Abstraction sur la source distante des guides (Firestore en production).
protocol GuideRemoteRepository: Sendable {
    func fetchAll() async throws -> [Guide]
}
