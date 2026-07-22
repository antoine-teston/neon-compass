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
    private(set) var foundPOIIDs: Set<String>

    private let modelContext: ModelContext

    init(pois: [POI], modelContext: ModelContext) {
        self.pois = pois
        self.activeCategories = Set(POICategory.allCases)
        self.modelContext = modelContext
        self.foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var filteredPOIs: [POI] {
        let languageCode = currentLanguageCode
        return pois.filter { poi in
            poi.position != nil
                && activeCategories.contains(poi.category)
                && (searchQuery.isEmpty
                    || poi.title.resolved(for: languageCode).localizedCaseInsensitiveContains(searchQuery))
        }
    }

    func isFound(_ poi: POI) -> Bool {
        foundPOIIDs.contains(poi.id)
    }

    func toggleFound(_ poi: POI) {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            foundPOIIDs.remove(poiID)
        } else {
            modelContext.insert(FoundEntry(poiID: poi.id))
            foundPOIIDs.insert(poiID)
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

    func updatePOIs(_ newPOIs: [POI]) {
        pois = newPOIs
    }
}
