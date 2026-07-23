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
    private let widgetSummaryCoordinator: WidgetSummaryCoordinator?

    init(
        pois: [POI],
        trophies: [Trophy],
        modelContext: ModelContext,
        widgetSummaryCoordinator: WidgetSummaryCoordinator? = nil
    ) {
        self.pois = pois
        self.trophies = trophies
        self.modelContext = modelContext
        self.widgetSummaryCoordinator = widgetSummaryCoordinator
        self.foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
        self.checkedTrophyIDs = Set((try? modelContext.fetch(FetchDescriptor<TrophyProgress>()))?.map(\.trophyID) ?? [])
        notifyWidgetProgress()
    }

    func refreshFoundState() {
        foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
        notifyWidgetProgress()
    }

    func updatePOIs(_ newPOIs: [POI]) {
        pois = newPOIs
        notifyWidgetProgress()
    }

    private func notifyWidgetProgress() {
        widgetSummaryCoordinator?.updateProgress(overallProgress)
    }

    func updateTrophies(_ newTrophies: [Trophy]) {
        trophies = newTrophies
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
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            checkedTrophyIDs.remove(trophyID)
        } else {
            modelContext.insert(TrophyProgress(trophyID: trophyID))
            checkedTrophyIDs.insert(trophyID)
        }
        try? modelContext.save()
    }
}
