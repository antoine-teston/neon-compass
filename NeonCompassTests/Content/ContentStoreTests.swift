import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct ContentStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([ContentCacheEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func samplePOI(id: String, x: Double = 0.1, deleted: Bool? = nil) -> POI {
        POI(id: id, category: .landmark, position: NormalizedPoint(x: x, y: 0.1),
            title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil,
            deleted: deleted)
    }

    @Test func startsEmptyWithNoCacheAndVersionZero() {
        let remote = FakeContentRepository<POI>()
        let version = FakeContentVersionProvider()
        let store = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: makeContext())
        #expect(store.items.isEmpty)
    }

    @Test func syncFetchesAndCachesWhenRemoteVersionIsNewer() async throws {
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let store = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: makeContext())

        try await store.syncIfNeeded()

        #expect(store.items.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func syncIsNoOpWhenVersionUnchanged() async throws {
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()
        let store = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        try await store.syncIfNeeded()

        let secondStore = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        try await secondStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)
    }

    @Test func loadsFromCacheOnInitWithoutNetworkCall() async throws {
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let firstStore = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        try await firstStore.syncIfNeeded()

        let secondStore = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        #expect(secondStore.items.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func differentCollectionNamesDoNotShareCache() async throws {
        let context = makeContext()
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1

        let poiStore = ContentStore<POI>(collectionName: "poi", remote: remote, versionProvider: version, modelContext: context)
        try await poiStore.syncIfNeeded()

        // Un store pour une autre collectionName ne doit jamais lire la ligne
        // ContentCacheEntry d'une autre collection — c'est le comportement
        // clé à préserver maintenant qu'un seul type de modèle sert toutes
        // les collections de contenu (avant : 3 types de modèle distincts,
        // l'isolation était structurelle plutôt que par clé).
        let otherStore = ContentStore<POI>(collectionName: "other", remote: remote, versionProvider: version, modelContext: context)
        #expect(otherStore.items.isEmpty)
    }

    @Test func exposesTheSeedBeforeAnySync() {
        // Premier lancement, sans réseau : la carte de référence doit déjà être
        // explorable.
        let store = ContentStore<POI>(
            collectionName: "poi_gtav",
            seed: [samplePOI(id: "socle")],
            remote: FakeContentRepository<POI>(),
            versionProvider: FakeContentVersionProvider(),
            modelContext: makeContext()
        )
        #expect(store.items.map(\.id) == ["socle"])
    }

    @Test func syncPatchesTheSeedInsteadOfReplacingIt() async throws {
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "b", x: 0.9), samplePOI(id: "neuf")]
        let version = FakeContentVersionProvider()
        version.version = 1

        let store = ContentStore<POI>(
            collectionName: "poi_gtav",
            seed: [samplePOI(id: "a"), samplePOI(id: "b", x: 0.1)],
            remote: remote,
            versionProvider: version,
            modelContext: makeContext()
        )
        try await store.syncIfNeeded()

        #expect(store.items.map(\.id) == ["a", "b", "neuf"])
        #expect(store.items[1].position?.x == 0.9)
    }

    @Test func cachesTheOverlayNotTheMergedResult() async throws {
        // Le point qui compte : si le cache portait le résultat fusionné, une
        // mise à jour de l'app livrant un socle enrichi serait masquée par un
        // cache écrit à l'époque de l'ancien socle, jusqu'au prochain bump de
        // version. Ici le second store a un socle plus large et doit le voir.
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "patch")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let first = ContentStore<POI>(
            collectionName: "poi_gtav",
            seed: [samplePOI(id: "a")],
            remote: remote,
            versionProvider: version,
            modelContext: context
        )
        try await first.syncIfNeeded()
        #expect(first.items.map(\.id) == ["a", "patch"])

        let afterAppUpdate = ContentStore<POI>(
            collectionName: "poi_gtav",
            seed: [samplePOI(id: "a"), samplePOI(id: "b")],
            remote: remote,
            versionProvider: version,
            modelContext: context
        )
        #expect(afterAppUpdate.items.map(\.id) == ["a", "b", "patch"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func aRemoteTombstoneRemovesASeedEntry() async throws {
        let remote = FakeContentRepository<POI>()
        remote.itemsToReturn = [samplePOI(id: "a", deleted: true)]
        let version = FakeContentVersionProvider()
        version.version = 1

        let store = ContentStore<POI>(
            collectionName: "poi_gtav",
            seed: [samplePOI(id: "a"), samplePOI(id: "b")],
            remote: remote,
            versionProvider: version,
            modelContext: makeContext()
        )
        try await store.syncIfNeeded()
        #expect(store.items.map(\.id) == ["b"])
    }
}
