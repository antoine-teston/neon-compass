import Testing
@testable import NeonCompass

final class FakeContentVersionProvider: ContentVersionProviding {
    nonisolated(unsafe) var version: Int = 0
    func currentVersion() -> Int { version }
}

final class FakePOIRemoteRepository: POIRemoteRepository {
    nonisolated(unsafe) var poisToReturn: [POI] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [POI] {
        fetchCallCount += 1
        return poisToReturn
    }
}

struct FakesTests {
    @Test func versionProviderReturnsSetValue() {
        let fake = FakeContentVersionProvider()
        fake.version = 5
        #expect(fake.currentVersion() == 5)
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
