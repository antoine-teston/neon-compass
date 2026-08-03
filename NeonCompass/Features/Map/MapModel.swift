import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class MapModel {
    private(set) var pois: [POI]
    var activeCategories: Set<POICategory> {
        didSet { refreshFilteredPOIs() }
    }
    var searchQuery: String = "" {
        didSet { refreshFilteredPOIs() }
    }
    var selectedPOI: POI?
    private(set) var foundPOIIDs: Set<String>
    var hideFoundPOIs = false {
        didSet { refreshFilteredPOIs() }
    }

    // MARK: - Vues dérivées, STOCKÉES et non calculées
    //
    // Ces deux valeurs étaient des propriétés calculées lues à chaque rendu de
    // `MapScreen` — et `MapScreen` se réévalue pour quantité de raisons
    // étrangères à la carte : présenter une feuille, ouvrir une alerte, et
    // surtout FRAPPER UN CARACTÈRE dans le champ de nom d'une épingle, dont le
    // `@State` vit sur l'écran. Chaque caractère payait donc une requête
    // SwiftData plus un filtrage des 537 points.
    //
    // Mesuré à la sonde : chaque étape du flux « ajouter une épingle »
    // (appui long, ouverture du menu, ouverture de l'alerte) déclenchait un
    // rendu complet, et donc une requête et un filtrage de plus.
    //
    // Même correctif que `CheatsModel` et `FeedModel` : on stocke, et on
    // recalcule aux seuls moments où une entrée change.
    private(set) var filteredPOIs: [POI] = []
    /// Incrémenté à chaque reconstruction de `filteredPOIs`. Sert de clé
    /// d'invalidation à `MapClusterCache` : comparer 537 points pour détecter un
    /// changement coûterait le prix d'un recalcul, ce compteur coûte zéro.
    private(set) var poisGeneration = 0
    /// Une requête SwiftData n'a rien à faire dans une propriété lue par le
    /// corps d'une vue : c'est de l'entrée/sortie sur le fil principal, à
    /// chaque rendu.
    private(set) var personalPins: [PersonalPin] = []
    /// Même rôle que `poisGeneration`, pour les épingles personnelles : donner
    /// au moteur de carte un moyen en O(1) de savoir si sa liste a changé.
    /// `PersonalPin` est une classe SwiftData — comparer les tableaux ne dirait
    /// rien d'un titre modifié, et compter les éléments encore moins.
    private(set) var personalPinsGeneration = 0

    private let modelContext: ModelContext
    private var sync: ProgressionSyncing?

    init(pois: [POI], modelContext: ModelContext, sync: ProgressionSyncing? = nil) {
        self.pois = pois
        self.activeCategories = Set(POICategory.allCases)
        self.modelContext = modelContext
        self.sync = sync
        self.foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
        // Les `didSet` ne se déclenchent pas pendant l'initialisation.
        refreshFilteredPOIs()
        refreshPersonalPins()
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

    private func refreshFilteredPOIs() {
        let languageCode = currentLanguageCode
        filteredPOIs = pois.filter { poi in
            poi.position != nil
                && activeCategories.contains(poi.category)
                && !(hideFoundPOIs && isFound(poi))
                && (searchQuery.isEmpty
                    || poi.title.resolved(for: languageCode).localizedCaseInsensitiveContains(searchQuery))
        }
        poisGeneration &+= 1
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
        // Le filtrage ne dépend de l'état « trouvé » QUE sous « masquer les
        // trouvés » — et rien d'autre ne s'y rejoue.
        //
        // Le refiltrage était inconditionnel, et c'était la lenteur du marquage :
        // il fait avancer `poisGeneration`, ce qui périme le cache de groupes
        // (`MapClusterCache`) et réagrège les cinq cent trente-sept points, pour
        // un changement qui n'ôte ni n'ajoute un seul point à la liste dessinée.
        // Hors de ce mode, l'état voyage désormais par `foundPOIIDs`, que le
        // jeton de contenu du moteur compare directement.
        if hideFoundPOIs {
            refreshFilteredPOIs()
        }
    }

    private func refreshPersonalPins() {
        let descriptor = FetchDescriptor<PersonalPin>(sortBy: [SortDescriptor(\.createdAt)])
        personalPins = (try? modelContext.fetch(descriptor)) ?? []
        personalPinsGeneration &+= 1
    }

    func addPersonalPin(at point: NormalizedPoint, title: String) {
        modelContext.insert(PersonalPin(x: point.x, y: point.y, title: title))
        try? modelContext.save()
        refreshPersonalPins()
    }

    func deletePersonalPin(_ pin: PersonalPin) {
        modelContext.delete(pin)
        try? modelContext.save()
        refreshPersonalPins()
    }

    func updatePOIs(_ newPOIs: [POI]) {
        pois = newPOIs
        refreshFilteredPOIs()
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
        refreshFilteredPOIs()
    }
}
