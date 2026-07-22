import Testing
import SwiftData
@testable import NeonCompass

final class FakeGuideRemoteRepository: GuideRemoteRepository {
    nonisolated(unsafe) var guidesToReturn: [Guide] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [Guide] {
        fetchCallCount += 1
        return guidesToReturn
    }
}

@MainActor
struct GuideContentStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([GuideCacheEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func sampleGuide(id: String) -> Guide {
        Guide(id: id, chapter: .beginner,
              title: LocalizedText(en: "Sample", fr: nil, es: nil, it: nil, de: nil),
              body: LocalizedText(en: "# Sample body", fr: nil, es: nil, it: nil, de: nil))
    }

    @Test func startsEmptyWithNoCacheAndVersionZero() {
        let remote = FakeGuideRemoteRepository()
        let version = FakeContentVersionProvider()
        let store = GuideContentStore(remote: remote, versionProvider: version, modelContext: makeContext())
        #expect(store.guides.isEmpty)
    }

    @Test func syncFetchesAndCachesWhenRemoteVersionIsNewer() async throws {
        let remote = FakeGuideRemoteRepository()
        remote.guidesToReturn = [sampleGuide(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let store = GuideContentStore(remote: remote, versionProvider: version, modelContext: makeContext())

        try await store.syncIfNeeded()

        #expect(store.guides.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func syncIsNoOpWhenVersionUnchanged() async throws {
        let remote = FakeGuideRemoteRepository()
        remote.guidesToReturn = [sampleGuide(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()
        let store = GuideContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await store.syncIfNeeded()

        let secondStore = GuideContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await secondStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)
    }

    @Test func loadsFromCacheOnInitWithoutNetworkCall() async throws {
        let remote = FakeGuideRemoteRepository()
        remote.guidesToReturn = [sampleGuide(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let firstStore = GuideContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await firstStore.syncIfNeeded()

        let secondStore = GuideContentStore(remote: remote, versionProvider: version, modelContext: context)
        #expect(secondStore.guides.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }
}
