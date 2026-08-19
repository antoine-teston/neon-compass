import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ProgressionModel {
    /// **Par jeu, et non fusionné.** `POI` n'a pas de champ `game` : le jeu se
    /// déduit du magasin d'où le POI vient, et l'appelant construit déjà les
    /// deux magasins séparément. Les fusionner ici perdait cette information —
    /// et avec elle tout compte par jeu, puisqu'un POI GTA VI a
    /// `collection: nil` par défaut et ne se rattache donc à aucun défi.
    private(set) var poisByGame: [Game: [POI]]
    private(set) var collections: [POICollection]

    /// Recalculé quand `(pois, foundIDs)` change, jamais à la lecture.
    /// Les vues le lisent plusieurs fois par rendu ; le laisser en propriété
    /// calculée rebalayait tout le tableau de POI à chaque accès.
    private(set) var challenges: [ChallengeProgress] = []

    /// Tous les POI, dans l'ordre de `Game`. Le calcul des défis n'a pas besoin
    /// de la distinction — une collection porte déjà son jeu.
    var pois: [POI] { Game.allCases.flatMap { poisByGame[$0] ?? [] } }

    /// Passe-plat vers le magasin partagé — voir `FoundStore` pour la divergence
    /// que ce partage referme.
    var foundPOIIDs: Set<String> { found.foundIDs }
    private let modelContext: ModelContext
    private let found: FoundStore
    private let widgetSummaryCoordinator: WidgetSummaryCoordinator?
    private var sync: ProgressionSyncing?

    /// `found` facultatif pour les mêmes raisons que dans `MapModel` : les tests
    /// veulent un magasin isolé, la production fournit celui de l'app.
    init(
        poisByGame: [Game: [POI]],
        collections: [POICollection] = POICollectionLoader.bundled,
        modelContext: ModelContext,
        found: FoundStore? = nil,
        sync: ProgressionSyncing? = nil,
        widgetSummaryCoordinator: WidgetSummaryCoordinator? = nil
    ) {
        self.poisByGame = poisByGame
        self.collections = collections
        self.modelContext = modelContext
        self.found = found ?? FoundStore(modelContext: modelContext)
        self.sync = sync
        self.widgetSummaryCoordinator = widgetSummaryCoordinator
        recomputeChallenges()
    }

    /// Recalcule les défis depuis l'état « trouvé ».
    ///
    /// Relit le disque au passage, ce qui reste utile même avec un magasin
    /// partagé : le chemin d'amorçage du widget écrit avec son propre
    /// `ProgressionModel` jetable, et les tests insèrent des `FoundEntry`
    /// directement. Voir `FoundStore.refresh()`.
    func refreshFoundState() {
        found.refresh()
        recomputeChallenges()
    }

    func updatePOIs(_ newPOIsByGame: [Game: [POI]]) {
        poisByGame = newPOIsByGame
        recomputeChallenges()
    }

    /// Lieux cochés d'un jeu, comptés sur ses POI et **non sur ses défis**.
    ///
    /// La distinction n'est pas cosmétique : les quinze collections publiées
    /// sont toutes GTA V, donc compter par défi rendrait le volet à venir
    /// éternellement à zéro alors que ses POI se cochent déjà sur la carte.
    func foundCount(for game: Game) -> Int {
        let ids = foundPOIIDs
        return (poisByGame[game] ?? []).count { ids.contains($0.id) }
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

    private func notifyWidgetProgress() {
        widgetSummaryCoordinator?.updateProgress(overallProgress)
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

    /// Réconciliation dernier-écrit-gagne des éléments distants, déléguée au
    /// magasin partagé.
    ///
    /// Elle ne traitait QUE les trophées avant le 2026-08-19, ce qui laissait un
    /// trou : la progression distante des POI n'était tirée que par le chemin de
    /// la carte, donc ouvrir le Profil sans passer par la carte ne rapatriait
    /// rien. Le retrait des trophées met la méthode face à ce trou plutôt que de
    /// le masquer. `FoundStore.reconcile` est idempotent et dernier-écrit-gagne,
    /// donc l'appeler depuis les deux chemins est sans conséquence.
    ///
    /// Les lignes `kind = 'trophy'` restées en base n'arrivent même pas jusqu'ici :
    /// `SupabaseProgressionSync.fetchAll` écarte déjà toute sorte inconnue.
    ///
    /// Recalculer ensuite garde l'invariant « `challenges` reflète toujours
    /// `(pois, foundPOIIDs)` » vrai à tout instant.
    func reconcile(with remoteItems: [ProgressionSyncItem]) {
        found.reconcile(with: remoteItems)
        recomputeChallenges()
    }
}
