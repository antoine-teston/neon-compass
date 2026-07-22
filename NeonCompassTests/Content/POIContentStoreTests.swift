import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct POIContentStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([POICacheEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func samplePOI(id: String) -> POI {
        POI(id: id, category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
            title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func startsEmptyWithNoCacheAndVersionZero() {
        let remote = FakePOIRemoteRepository()
        let version = FakeContentVersionProvider()
        let store = POIContentStore(remote: remote, versionProvider: version, modelContext: makeContext())
        #expect(store.pois.isEmpty)
    }

    @Test func syncFetchesAndCachesWhenRemoteVersionIsNewer() async throws {
        let remote = FakePOIRemoteRepository()
        remote.poisToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let store = POIContentStore(remote: remote, versionProvider: version, modelContext: makeContext())

        try await store.syncIfNeeded()

        #expect(store.pois.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func syncIsNoOpWhenVersionUnchanged() async throws {
        let remote = FakePOIRemoteRepository()
        remote.poisToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()
        let store = POIContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await store.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)

        // Un second store réutilisant le même contexte (donc le même cache
        // persisté) avec une version distante inchangée ne doit pas re-fetcher.
        let secondStore = POIContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await secondStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)
    }

    @Test func loadsFromCacheOnInitWithoutNetworkCall() async throws {
        let remote = FakePOIRemoteRepository()
        remote.poisToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let firstStore = POIContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await firstStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)

        // Un nouveau store sur le même contexte doit charger depuis le cache
        // dès l'init, sans appel réseau — l'app doit être utilisable hors-ligne.
        let secondStore = POIContentStore(remote: remote, versionProvider: version, modelContext: context)
        #expect(secondStore.pois.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }
}
