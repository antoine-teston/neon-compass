// Doublures partagées par les suites de `Content/`. Aucun test ici : ce fichier
// ne porte que les fakes.

@testable import NeonCompass

final class FakeContentVersionProvider: ContentVersionProviding {
    nonisolated(unsafe) var version: Int = 0
    nonisolated(unsafe) private(set) var invalidateCallCount = 0
    func currentVersion() async throws -> Int { version }
    func invalidate() async { invalidateCallCount += 1 }
}

final class FakeContentRepository<Item: Sendable>: ContentRemoteRepository {
    nonisolated(unsafe) var itemsToReturn: [Item] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [Item] {
        fetchCallCount += 1
        return itemsToReturn
    }
}
