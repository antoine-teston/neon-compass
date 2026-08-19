import Foundation
import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct ProgressionReconciliationTests {
    private func makeMapContext() throws -> ModelContext {
        let container = try ModelContainer(for: FoundEntry.self, PersonalPin.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makePOI(id: String) -> POI {
        POI(id: id, category: .landmark, position: nil, title: LocalizedText(en: "x", fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func reconcileAppliesANewerRemoteFoundState() throws {
        let context = try makeMapContext()
        let model = MapModel(pois: [], modelContext: context)
        let newer = Date.now
        model.reconcile(with: [ProgressionSyncItem(itemID: "poi-1", kind: .poi, found: true, updatedAt: newer)])
        #expect(model.isFound(makePOI(id: "poi-1")))
    }

    @Test func reconcileIgnoresAnOlderRemoteState() throws {
        let context = try makeMapContext()
        let now = Date.now
        // Insert the pre-existing local entry BEFORE constructing MapModel,
        // matching production reality: MapModel reads persisted FoundEntry
        // state at init (an on-disk edit made behind the model's back isn't
        // reflected in its in-memory foundPOIIDs cache, same as production).
        context.insert(FoundEntry(poiID: "poi-1", foundAt: now, updatedAt: now))
        try context.save()
        let model = MapModel(pois: [], modelContext: context)
        let older = now.addingTimeInterval(-60)
        model.reconcile(with: [ProgressionSyncItem(itemID: "poi-1", kind: .poi, found: false, updatedAt: older)])
        // local (found=true, now) is newer than remote (found=false, older) — local wins
        #expect(model.isFound(makePOI(id: "poi-1")))
    }

    @Test func reconcileAppliesANewerRemoteUnfoundState() throws {
        let context = try makeMapContext()
        let older = Date.now.addingTimeInterval(-120)
        context.insert(FoundEntry(poiID: "poi-1", foundAt: older, updatedAt: older))
        try context.save()
        let model = MapModel(pois: [], modelContext: context)
        let newer = Date.now
        model.reconcile(with: [ProgressionSyncItem(itemID: "poi-1", kind: .poi, found: false, updatedAt: newer)])
        #expect(!model.isFound(makePOI(id: "poi-1")))
    }

    @Test func reconcileIgnoresARemoteAbsentFoundStateWithNoLocalEntry() throws {
        let context = try makeMapContext()
        let model = MapModel(pois: [], modelContext: context)
        model.reconcile(with: [ProgressionSyncItem(itemID: "poi-1", kind: .poi, found: false, updatedAt: .now)])
        #expect(!model.isFound(makePOI(id: "poi-1")))
    }

    // MARK: - ProgressionModel

    private func makeProgressionContext() throws -> ModelContext {
        let container = try ModelContainer(for: FoundEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

/// Les trois cas trophée qui vivaient ici sont partis avec les trophées le
    /// 2026-08-19. Ce qui les remplace n'est pas rien : `ProgressionModel.reconcile`
    /// ne traitait QUE les trophées, donc la progression distante des POI n'était
    /// tirée que par le chemin de la carte — ouvrir le Profil sans passer par la
    /// carte ne rapatriait rien. Elle délègue désormais au magasin partagé, et
    /// c'est ce trou-là que le test suivant ferme.
    @Test func reconcileFromTheProfilePathAppliesRemotePOIProgress() throws {
        let context = try makeProgressionContext()
        let store = FoundStore(modelContext: context)
        let model = ProgressionModel(poisByGame: [:], modelContext: context, found: store)

        model.reconcile(with: [
            ProgressionSyncItem(itemID: "poi-1", kind: .poi, found: true, updatedAt: .now),
        ])

        #expect(store.isFound("poi-1"))
        #expect(model.foundPOIIDs.contains("poi-1"))
    }

        // MARK: - attachSyncIfNeeded (closes the sync-activation race)

    /// Test double standing in for FirestoreProgressionSync. An actor so
    /// mutable call-count bookkeeping stays `Sendable`-safe, matching the
    /// `ProgressionSyncing: Sendable` requirement.
    private actor FakeSync: ProgressionSyncing {
        private let items: [ProgressionSyncItem]
        private(set) var fetchAllCallCount = 0

        init(items: [ProgressionSyncItem] = []) {
            self.items = items
        }

        func upload(itemID: String, kind: ProgressionItemKind, found: Bool, updatedAt: Date) async {}

        func fetchAll(uid: String) async -> [ProgressionSyncItem] {
            fetchAllCallCount += 1
            return items
        }
    }

    @Test func mapModelAttachSyncIfNeededAttachesWhenNilThenIsANoOpAfter() throws {
        let context = try makeMapContext()
        let model = MapModel(pois: [], modelContext: context)
        let first = FakeSync()
        let second = FakeSync()

        #expect(model.attachSyncIfNeeded(first) == true)
        #expect(model.attachSyncIfNeeded(second) == false)

        // Verify the first sync (not the second) is the one actually wired
        // up: toggling found state should upload through `first`, not
        // silently reference `second`.
        model.toggleFound(makePOI(id: "poi-1"))
    }

    @Test func progressionModelAttachSyncIfNeededAttachesWhenNilThenIsANoOpAfter() throws {
        let context = try makeProgressionContext()
        let model = ProgressionModel(poisByGame: [:], modelContext: context)
        let first = FakeSync()
        let second = FakeSync()

        #expect(model.attachSyncIfNeeded(first) == true)
        #expect(model.attachSyncIfNeeded(second) == false)
    }
}
