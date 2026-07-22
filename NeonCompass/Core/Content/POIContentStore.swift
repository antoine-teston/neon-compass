import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class POIContentStore {
    private static let collectionName = "poi"

    private(set) var pois: [POI]

    private let remote: POIRemoteRepository
    private let versionProvider: ContentVersionProviding
    private let modelContext: ModelContext

    init(remote: POIRemoteRepository, versionProvider: ContentVersionProviding, modelContext: ModelContext) {
        self.remote = remote
        self.versionProvider = versionProvider
        self.modelContext = modelContext
        self.pois = Self.loadCached(from: modelContext)
    }

    func syncIfNeeded() async throws {
        let remoteVersion = try await versionProvider.currentVersion()
        let localVersion = Self.cachedVersion(from: modelContext)
        guard remoteVersion > localVersion else { return }

        let fetched = try await remote.fetchAll()
        let data = try JSONEncoder().encode(fetched)

        let name = Self.collectionName
        let descriptor = FetchDescriptor<POICacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.json = data
            existing.version = remoteVersion
        } else {
            modelContext.insert(POICacheEntry(collectionName: Self.collectionName, json: data, version: remoteVersion))
        }
        try modelContext.save()

        pois = fetched
    }

    private static func loadCached(from modelContext: ModelContext) -> [POI] {
        let name = collectionName
        let descriptor = FetchDescriptor<POICacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let decoded = try? JSONDecoder().decode([POI].self, from: entry.json) else {
            return []
        }
        return decoded
    }

    private static func cachedVersion(from modelContext: ModelContext) -> Int {
        let name = collectionName
        let descriptor = FetchDescriptor<POICacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        return (try? modelContext.fetch(descriptor).first?.version) ?? 0
    }
}
