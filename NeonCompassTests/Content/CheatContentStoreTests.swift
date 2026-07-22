import Testing
import SwiftData
@testable import NeonCompass

final class FakeCheatRemoteRepository: CheatRemoteRepository {
    nonisolated(unsafe) var cheatsToReturn: [Cheat] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [Cheat] {
        fetchCallCount += 1
        return cheatsToReturn
    }
}

@MainActor
struct CheatContentStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([CheatCacheEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func sampleCheat(id: String) -> Cheat {
        Cheat(id: id, category: .misc,
              effect: LocalizedText(en: "Sample", fr: nil, es: nil, it: nil, de: nil),
              sequence: [.ps5: [.up], .xbox: [.up]], blocksTrophies: false)
    }

    @Test func startsEmptyWithNoCacheAndVersionZero() {
        let remote = FakeCheatRemoteRepository()
        let version = FakeContentVersionProvider()
        let store = CheatContentStore(remote: remote, versionProvider: version, modelContext: makeContext())
        #expect(store.cheats.isEmpty)
    }

    @Test func syncFetchesAndCachesWhenRemoteVersionIsNewer() async throws {
        let remote = FakeCheatRemoteRepository()
        remote.cheatsToReturn = [sampleCheat(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let store = CheatContentStore(remote: remote, versionProvider: version, modelContext: makeContext())

        try await store.syncIfNeeded()

        #expect(store.cheats.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func syncIsNoOpWhenVersionUnchanged() async throws {
        let remote = FakeCheatRemoteRepository()
        remote.cheatsToReturn = [sampleCheat(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()
        let store = CheatContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await store.syncIfNeeded()

        let secondStore = CheatContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await secondStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)
    }

    @Test func loadsFromCacheOnInitWithoutNetworkCall() async throws {
        let remote = FakeCheatRemoteRepository()
        remote.cheatsToReturn = [sampleCheat(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let firstStore = CheatContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await firstStore.syncIfNeeded()

        let secondStore = CheatContentStore(remote: remote, versionProvider: version, modelContext: context)
        #expect(secondStore.cheats.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }
}
