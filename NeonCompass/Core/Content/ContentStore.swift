import Foundation
import Observation
import SwiftData

/// Store générique offline-first pour un type de contenu Firestore.
/// Remplace les trois implémentations dupliquées
/// (POIContentStore/CheatContentStore/GuideContentStore) — identiques à un
/// renommage de type près. `collectionName` est maintenant un paramètre
/// d'instance (au lieu d'une constante statique par type) puisqu'un seul
/// type générique sert toutes les collections.
@Observable
@MainActor
final class ContentStore<Item: Codable & Sendable> {
    private let collectionName: String
    private(set) var items: [Item]

    private let remote: any ContentRemoteRepository<Item>
    private let versionProvider: ContentVersionProviding
    private let modelContext: ModelContext

    init(
        collectionName: String,
        remote: any ContentRemoteRepository<Item>,
        versionProvider: ContentVersionProviding,
        modelContext: ModelContext
    ) {
        self.collectionName = collectionName
        self.remote = remote
        self.versionProvider = versionProvider
        self.modelContext = modelContext
        self.items = Self.loadCached(collectionName: collectionName, from: modelContext)
    }

    func syncIfNeeded() async throws {
        let remoteVersion = try await versionProvider.currentVersion()
        let localVersion = Self.cachedVersion(collectionName: collectionName, from: modelContext)
        guard remoteVersion > localVersion else { return }

        let fetched = try await remote.fetchAll()
        let data = try JSONEncoder().encode(fetched)

        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.json = data
            existing.version = remoteVersion
        } else {
            modelContext.insert(ContentCacheEntry(collectionName: name, json: data, version: remoteVersion))
        }
        try modelContext.save()

        items = fetched
    }

    private static func loadCached(collectionName: String, from modelContext: ModelContext) -> [Item] {
        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let decoded = try? JSONDecoder().decode([Item].self, from: entry.json) else {
            return []
        }
        return decoded
    }

    private static func cachedVersion(collectionName: String, from modelContext: ModelContext) -> Int {
        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        return (try? modelContext.fetch(descriptor).first?.version) ?? 0
    }
}
