import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ProgressionModel {
    private(set) var pois: [POI]
    private(set) var trophies: [Trophy]
    private(set) var checkedTrophyIDs: Set<String>

    private(set) var foundPOIIDs: Set<String>
    private let modelContext: ModelContext
    private var sync: ProgressionSyncing?

    init(pois: [POI], trophies: [Trophy], modelContext: ModelContext, sync: ProgressionSyncing? = nil) {
        self.pois = pois
        self.trophies = trophies
        self.modelContext = modelContext
        self.sync = sync
        self.foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
        self.checkedTrophyIDs = Set((try? modelContext.fetch(FetchDescriptor<TrophyProgress>()))?.map(\.trophyID) ?? [])
    }

    func refreshFoundState() {
        foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
    }

    func updatePOIs(_ newPOIs: [POI]) {
        pois = newPOIs
    }

    func updateTrophies(_ newTrophies: [Trophy]) {
        trophies = newTrophies
    }

    /// Attaches sync after construction if it wasn't available yet at init
    /// time (closes the race where the Pro entitlement/auth gate becomes
    /// true only after `loadModel()` already ran once with `sync == nil`).
    /// Idempotent: a no-op if sync is already attached. Returns whether this
    /// call actually attached sync, so the caller knows whether it also
    /// needs to trigger an initial pull + reconcile.
    @discardableResult
    func attachSyncIfNeeded(_ sync: ProgressionSyncing) -> Bool {
        guard self.sync == nil else { return false }
        self.sync = sync
        return true
    }

    var overallProgress: Double {
        guard !pois.isEmpty else { return 0 }
        return Double(pois.filter { foundPOIIDs.contains($0.id) }.count) / Double(pois.count)
    }

    func progress(in category: POICategory) -> Double {
        let categoryPOIs = pois.filter { $0.category == category }
        guard !categoryPOIs.isEmpty else { return 0 }
        let foundCount = categoryPOIs.filter { foundPOIIDs.contains($0.id) }.count
        return Double(foundCount) / Double(categoryPOIs.count)
    }

    func isTrophyChecked(_ trophy: Trophy) -> Bool {
        checkedTrophyIDs.contains(trophy.id)
    }

    func toggleTrophy(_ trophy: Trophy) {
        let trophyID = trophy.id
        let descriptor = FetchDescriptor<TrophyProgress>(predicate: #Predicate { $0.trophyID == trophyID })
        let now = Date.now
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            checkedTrophyIDs.remove(trophyID)
            try? modelContext.save()
            Task { await sync?.upload(itemID: trophyID, kind: .trophy, found: false, updatedAt: now) }
        } else {
            modelContext.insert(TrophyProgress(trophyID: trophyID, updatedAt: now))
            checkedTrophyIDs.insert(trophyID)
            try? modelContext.save()
            Task { await sync?.upload(itemID: trophyID, kind: .trophy, found: true, updatedAt: now) }
        }
    }

    /// Last-write-wins-per-item reconciliation of remote progression into the
    /// local TrophyProgress store. Pure/testable independent of Firestore —
    /// the caller (ProgressionScreen) is responsible for fetching remoteItems
    /// and gating this on Pro + signed-in.
    func reconcile(with remoteItems: [ProgressionSyncItem]) {
        for item in remoteItems where item.kind == .trophy {
            let trophyID = item.itemID
            let descriptor = FetchDescriptor<TrophyProgress>(predicate: #Predicate { $0.trophyID == trophyID })
            let existing = try? modelContext.fetch(descriptor).first

            if let existing, existing.updatedAt >= item.updatedAt {
                continue // local is at least as recent, local wins
            }

            if item.found {
                if let existing {
                    existing.updatedAt = item.updatedAt
                } else {
                    modelContext.insert(TrophyProgress(trophyID: trophyID, updatedAt: item.updatedAt))
                }
                checkedTrophyIDs.insert(trophyID)
            } else if let existing {
                modelContext.delete(existing)
                checkedTrophyIDs.remove(trophyID)
            }
        }
        try? modelContext.save()
    }
}
