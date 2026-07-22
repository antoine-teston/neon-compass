import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class GuideContentStore {
    private static let collectionName = "guides"

    private(set) var guides: [Guide]

    private let remote: GuideRemoteRepository
    private let versionProvider: ContentVersionProviding
    private let modelContext: ModelContext

    init(remote: GuideRemoteRepository, versionProvider: ContentVersionProviding, modelContext: ModelContext) {
        self.remote = remote
        self.versionProvider = versionProvider
        self.modelContext = modelContext
        self.guides = Self.loadCached(from: modelContext)
    }

    func syncIfNeeded() async throws {
        let remoteVersion = try await versionProvider.currentVersion()
        let localVersion = Self.cachedVersion(from: modelContext)
        guard remoteVersion > localVersion else { return }

        let fetched = try await remote.fetchAll()
        let data = try JSONEncoder().encode(fetched)

        let name = Self.collectionName
        let descriptor = FetchDescriptor<GuideCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.json = data
            existing.version = remoteVersion
        } else {
            modelContext.insert(GuideCacheEntry(collectionName: Self.collectionName, json: data, version: remoteVersion))
        }
        try modelContext.save()

        guides = fetched
    }

    private static func loadCached(from modelContext: ModelContext) -> [Guide] {
        let name = collectionName
        let descriptor = FetchDescriptor<GuideCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let decoded = try? JSONDecoder().decode([Guide].self, from: entry.json) else {
            return []
        }
        return decoded
    }

    private static func cachedVersion(from modelContext: ModelContext) -> Int {
        let name = collectionName
        let descriptor = FetchDescriptor<GuideCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        return (try? modelContext.fetch(descriptor).first?.version) ?? 0
    }
}
