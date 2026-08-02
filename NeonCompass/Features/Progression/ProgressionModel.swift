import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ProgressionModel {
    private(set) var pois: [POI]
    private(set) var collections: [POICollection]
    private(set) var trophies: [Trophy]
    private(set) var checkedTrophyIDs: Set<String>

    /// Recalculé quand `(pois, foundIDs)` change, jamais à la lecture.
    /// Les vues le lisent plusieurs fois par rendu ; le laisser en propriété
    /// calculée rebalayait tout le tableau de POI à chaque accès.
    private(set) var challenges: [ChallengeProgress] = []

    private(set) var foundPOIIDs: Set<String>
    private let modelContext: ModelContext
    private let widgetSummaryCoordinator: WidgetSummaryCoordinator?
    private var sync: ProgressionSyncing?

    init(
        pois: [POI],
        collections: [POICollection] = POICollectionLoader.bundled,
        trophies: [Trophy],
        modelContext: ModelContext,
        sync: ProgressionSyncing? = nil,
        widgetSummaryCoordinator: WidgetSummaryCoordinator? = nil
    ) {
        self.pois = pois
        self.collections = collections
        self.trophies = trophies
        self.modelContext = modelContext
        self.sync = sync
        self.widgetSummaryCoordinator = widgetSummaryCoordinator
        self.foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
        self.checkedTrophyIDs = Set((try? modelContext.fetch(FetchDescriptor<TrophyProgress>()))?.map(\.trophyID) ?? [])
        recomputeChallenges()
    }

    func refreshFoundState() {
        foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
        recomputeChallenges()
    }

    func updatePOIs(_ newPOIs: [POI]) {
        pois = newPOIs
        recomputeChallenges()
    }

    /// Le catalogue arrive du canal de contenu : une collection GTA VI peut donc
    /// être déclarée sans mise à jour de l'app, le jour où on saura ce que ses
    /// POI sont.
    func updateCollections(_ newCollections: [POICollection]) {
        collections = newCollections
        recomputeChallenges()
    }

    private func recomputeChallenges() {
        challenges = ChallengeProgressCalculator.challenges(
            collections: collections,
            pois: pois,
            foundIDs: foundPOIIDs
        )
        notifyWidgetProgress()
    }

    /// Défis d'un jeu donné. La progression n'est jamais globale tous jeux
    /// confondus : mêler les fragments de lettre du volet précédent à un anneau
    /// de complétion du volet à venir ne voudrait rien dire.
    func challenges(for game: MapGame) -> [ChallengeProgress] {
        challenges.filter { $0.collection.game == game }
    }

    /// Jeux ayant au moins un défi à afficher, dans l'ordre de `MapGame`.
    var gamesWithChallenges: [MapGame] {
        MapGame.allCases.filter { game in challenges.contains { $0.collection.game == game } }
    }

    private func notifyWidgetProgress() {
        widgetSummaryCoordinator?.updateProgress(overallProgress)
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

    /// Chiffre unique du widget (`WidgetSummary` n'en prend qu'un).
    ///
    /// Priorité au jeu à venir dès qu'un de ses défis a un total connu ; sinon
    /// la carte de référence, seule à en avoir au lancement. Zéro seulement
    /// quand aucun défi n'a de total — auquel cas il n'y a rien à afficher.
    var overallProgress: Double {
        ChallengeProgressCalculator.overall(challenges(for: .leonida))
            ?? ChallengeProgressCalculator.overall(challenges(for: .reference))
            ?? 0
    }

    /// Avancement global d'un jeu, `nil` tant qu'aucun de ses défis n'a de total
    /// connu — l'écran affiche alors des décomptes bruts sans anneau.
    func overallProgress(for game: MapGame) -> Double? {
        ChallengeProgressCalculator.overall(challenges(for: game))
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
    /// the caller (ProgressionSection) is responsible for fetching remoteItems
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
        // La réconciliation ne touche que les trophées ici, mais l'appelant
        // (ProgressionSection) enchaîne avec refreshFoundState() pour les POI ;
        // recalculer maintenant garde l'invariant « challenges reflète toujours
        // (pois, foundPOIIDs) » vrai à tout instant.
        recomputeChallenges()
    }
}
