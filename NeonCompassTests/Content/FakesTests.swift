import Testing
@testable import NeonCompass

final class FakeContentVersionProvider: ContentVersionProviding {
    nonisolated(unsafe) var version: Int = 0
    func currentVersion() async throws -> Int { version }
}

final class FakePOIRemoteRepository: POIRemoteRepository {
    nonisolated(unsafe) var poisToReturn: [POI] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [POI] {
        fetchCallCount += 1
        return poisToReturn
    }
}

final class FakeContentRepository<Item: Sendable>: ContentRemoteRepository {
    nonisolated(unsafe) var itemsToReturn: [Item] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [Item] {
        fetchCallCount += 1
        return itemsToReturn
    }
}

struct FakesTests {
    @Test func versionProviderReturnsSetValue() async throws {
        let fake = FakeContentVersionProvider()
        fake.version = 5
        #expect(try await fake.currentVersion() == 5)
    }

    @Test func remoteRepositoryTracksFetchCallsAndReturnsSetPOIs() async throws {
        let fake = FakePOIRemoteRepository()
        let poi = POI(id: "a", category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
                      title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil)
        fake.poisToReturn = [poi]
        let result = try await fake.fetchAll()
        #expect(result == [poi])
        #expect(fake.fetchCallCount == 1)
    }
}
