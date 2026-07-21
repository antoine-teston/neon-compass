import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class MapModel {
    private(set) var pois: [POI]
    var activeCategories: Set<POICategory>
    var searchQuery: String = ""
    var selectedPOI: POI?

    private let modelContext: ModelContext

    init(pois: [POI], modelContext: ModelContext) {
        self.pois = pois
        self.activeCategories = Set(POICategory.allCases)
        self.modelContext = modelContext
    }

    var filteredPOIs: [POI] {
        pois.filter { poi in
            activeCategories.contains(poi.category)
                && (searchQuery.isEmpty || poi.title.en.localizedCaseInsensitiveContains(searchQuery))
        }
    }

    func isFound(_ poi: POI) -> Bool {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    func toggleFound(_ poi: POI) {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FoundEntry(poiID: poi.id))
        }
        try? modelContext.save()
    }

    var personalPins: [PersonalPin] {
        let descriptor = FetchDescriptor<PersonalPin>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func addPersonalPin(at point: NormalizedPoint, title: String) {
        modelContext.insert(PersonalPin(x: point.x, y: point.y, title: title))
        try? modelContext.save()
    }

    func deletePersonalPin(_ pin: PersonalPin) {
        modelContext.delete(pin)
        try? modelContext.save()
    }
}
