import Foundation

/// Abstraction sur la source distante des POI (Firestore en production).
protocol POIRemoteRepository: Sendable {
    func fetchAll() async throws -> [POI]
}
