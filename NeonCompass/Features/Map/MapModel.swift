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
    var hideFoundPOIs = false

    private let modelContext: ModelContext
    private var sync: ProgressionSyncing?

    init(pois: [POI], modelContext: ModelContext, sync: ProgressionSyncing? = nil) {
        self.pois = pois
        self.activeCategories = Set(POICategory.allCases)
        self.modelContext = modelContext
        self.sync = sync
        self.foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
    }

    /// Quels POI afficher pour la carte sélectionnée.
    ///
    /// La séparation est stricte et doit le rester : les positions de la
    /// fixture sont normalisées SUR la carte de référence. Les afficher sur le
    /// placeholder du jeu à venir poserait plus de mille pins à des endroits
    /// qui ne veulent rien dire. C'est pourquoi il n'y a délibérément aucun
    /// repli de l'un vers l'autre — une carte `leonida` sans contenu distant
    /// reste vide, et c'est le comportement correct.
    ///
    /// `reference` est en `@autoclosure` : décoder la fixture coûte un parse
    /// JSON de ~200 Ko, inutile quand on affiche l'autre carte.
    static func pois(for game: MapGame, remote: [POI], reference: @autoclosure () -> [POI]) -> [POI] {
        switch game {
        case .leonida: remote
        case .reference: reference()
        }
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var filteredPOIs: [POI] {
        let languageCode = currentLanguageCode
        return pois.filter { poi in
            poi.position != nil
                && activeCategories.contains(poi.category)
                && !(hideFoundPOIs && isFound(poi))
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
        let now = Date.now
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            foundPOIIDs.remove(poiID)
            try? modelContext.save()
            Task { await sync?.upload(itemID: poiID, kind: .poi, found: false, updatedAt: now) }
        } else {
            modelContext.insert(FoundEntry(poiID: poi.id, updatedAt: now))
            foundPOIIDs.insert(poiID)
            try? modelContext.save()
            Task { await sync?.upload(itemID: poiID, kind: .poi, found: true, updatedAt: now) }
        }
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

    /// Last-write-wins-per-item reconciliation of remote progression into the
    /// local FoundEntry store. Pure/testable independent of Firestore — the
    /// caller (MapScreen) is responsible for fetching remoteItems and gating
    /// this on Pro + signed-in.
    func reconcile(with remoteItems: [ProgressionSyncItem]) {
        for item in remoteItems where item.kind == .poi {
            let poiID = item.itemID
            let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
            let existing = try? modelContext.fetch(descriptor).first

            if let existing, existing.updatedAt >= item.updatedAt {
                continue // local is at least as recent, local wins
            }

            if item.found {
                if let existing {
                    existing.updatedAt = item.updatedAt
                } else {
                    modelContext.insert(FoundEntry(poiID: poiID, foundAt: item.updatedAt, updatedAt: item.updatedAt))
                }
                foundPOIIDs.insert(poiID)
            } else if let existing {
                modelContext.delete(existing)
                foundPOIIDs.remove(poiID)
            }
        }
        try? modelContext.save()
    }
}
