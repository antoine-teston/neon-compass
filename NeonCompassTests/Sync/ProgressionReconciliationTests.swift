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

    // MARK: - ProgressionModel / TrophyProgress

    private func makeProgressionContext() throws -> ModelContext {
        let container = try ModelContainer(for: FoundEntry.self, TrophyProgress.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func reconcileAppliesANewerRemoteTrophyCheckedState() throws {
        let context = try makeProgressionContext()
        let model = ProgressionModel(pois: [], trophies: [], modelContext: context)
        let newer = Date.now
        model.reconcile(with: [ProgressionSyncItem(itemID: "trophy-1", kind: .trophy, found: true, updatedAt: newer)])
        #expect(model.checkedTrophyIDs.contains("trophy-1"))
    }

    @Test func reconcileIgnoresAnOlderRemoteTrophyState() throws {
        let context = try makeProgressionContext()
        let now = Date.now
        // See reconcileIgnoresAnOlderRemoteState above for why the insert
        // happens before model construction.
        context.insert(TrophyProgress(trophyID: "trophy-1", updatedAt: now))
        try context.save()
        let model = ProgressionModel(pois: [], trophies: [], modelContext: context)
        let older = now.addingTimeInterval(-60)
        model.reconcile(with: [ProgressionSyncItem(itemID: "trophy-1", kind: .trophy, found: false, updatedAt: older)])
        #expect(model.checkedTrophyIDs.contains("trophy-1"))
    }

    @Test func reconcileAppliesANewerRemoteTrophyUncheckedState() throws {
        let context = try makeProgressionContext()
        let older = Date.now.addingTimeInterval(-120)
        context.insert(TrophyProgress(trophyID: "trophy-1", updatedAt: older))
        try context.save()
        let model = ProgressionModel(pois: [], trophies: [], modelContext: context)
        let newer = Date.now
        model.reconcile(with: [ProgressionSyncItem(itemID: "trophy-1", kind: .trophy, found: false, updatedAt: newer)])
        #expect(!model.checkedTrophyIDs.contains("trophy-1"))
    }
}
