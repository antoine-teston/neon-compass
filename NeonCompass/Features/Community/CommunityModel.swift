import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CommunityModel {
    private(set) var approvedSpots: [Contribution] = [] {
        didSet { refreshVisibleSpots() }
    }
    private(set) var myContributions: [Contribution] = []

    /// Mes votes, par identifiant de contribution. Vide hors connexion — et
    /// c'est le bon défaut : tout se retrouve alors dans « À découvrir ».
    private(set) var myVotes: [String: VoteDirection] = [:]
    private(set) var blockedAuthorUIDs: Set<String> {
        didSet { refreshVisibleSpots() }
    }
    private(set) var contributionsEnabled = true

    /// Les spots que la carte rend : approuvés, moins ceux des auteurs bloqués.
    /// Stocké et non calculé — cette liste est lue par le corps de la carte, qui
    /// se réévalue pour quantité de raisons étrangères aux spots.
    private(set) var visibleSpots: [Contribution] = []

    /// Clé d'invalidation de `MapClusterCache` pour la famille des
    /// contributions. Portée par les `didSet` des DEUX entrées plutôt que par
    /// des incréments dispersés dans chaque mutateur : c'est ce qui la rend
    /// exhaustive. En particulier `vote(on:)` n'écrit que
    /// `approvedSpots[index].upvotes` — une mutation du CONTENU d'un membre,
    /// invisible d'une comparaison de composition, mais qui traverse bien le
    /// `didSet` du tableau.
    private(set) var spotsGeneration = 0

    private let repository: ContributionRepository
    private let functions: ContributionFunctionsCalling
    private let gateProvider: CommunityGateProviding
    private let modelContext: ModelContext
    /// Les spots approuvés viennent des fragments, avec garde de version et
    /// cache SwiftData — plus d'une lecture par spot à chaque lancement.
    private let approvedStore: ContentStore<Contribution>

    init(
        repository: ContributionRepository,
        functions: ContributionFunctionsCalling,
        gateProvider: CommunityGateProviding,
        modelContext: ModelContext,
        approvedStore: ContentStore<Contribution>
    ) {
        self.repository = repository
        self.functions = functions
        self.gateProvider = gateProvider
        self.modelContext = modelContext
        self.approvedStore = approvedStore
        self.blockedAuthorUIDs = []
        // Le cache est disponible avant tout réseau : la carte porte ses spots
        // dès le premier rendu, y compris hors-ligne.
        self.approvedSpots = approvedStore.items
        self.refreshBlockedAuthors()
        // Les `didSet` ne se déclenchent pas pour les affectations faites depuis
        // l'initialiseur lui-même : sans cet appel, la carte ouvrirait sans le
        // moindre spot jusqu'à la première mutation.
        self.refreshVisibleSpots()
    }

    /// Câblage de production, en un seul endroit : les deux écrans qui
    /// construisent un `CommunityModel` (carte et profil) passaient sinon la même
    /// liste de dépendances, et le nom de collection des fragments s'y serait
    /// dupliqué.
    static func live(modelContext: ModelContext) -> CommunityModel {
        let collectionName = CommunityBundleVersionProvider.collectionName
        return CommunityModel(
            repository: SupabaseContributionRepository(),
            functions: SupabaseContributionFunctions(),
            gateProvider: SupabaseCommunityGateProvider(),
            modelContext: modelContext,
            approvedStore: ContentStore<Contribution>(
                collectionName: collectionName,
                remote: CommunityBundleRepository<Contribution>(),
                versionProvider: CommunityBundleVersionProvider(),
                modelContext: modelContext
            )
        )
    }

    func refreshContributionsEnabled() async {
        contributionsEnabled = (try? await gateProvider.isEnabled()) ?? true
    }

    func refreshBlockedAuthors() {
        blockedAuthorUIDs = Set((try? modelContext.fetch(FetchDescriptor<BlockedContributor>()))?.map(\.authorUid) ?? [])
    }

    private func refreshVisibleSpots() {
        visibleSpots = approvedSpots.filter { spot in
            guard let authorUid = spot.authorUid else { return true }
            return !blockedAuthorUIDs.contains(authorUid)
        }
        spotsGeneration &+= 1
    }

    /// Ne télécharge que si la version du manifeste a bougé — sinon la seule
    /// lecture facturée est celle du manifeste lui-même.
    func loadApprovedSpots() async {
        try? await approvedStore.syncIfNeeded()
        approvedSpots = approvedStore.items
    }

    func loadMyContributions(uid: String) async {
        myContributions = (try? await repository.fetchMine(uid: uid)) ?? []
    }

    /// L'heure du dernier envoi réussi, pour armer le cooldown AVANT le réseau :
    /// deux propositions d'affilée sur le même téléphone — le cas courant — ne
    /// partent jamais pour rien.
    ///
    /// En mémoire seulement. La fenêtre est de soixante secondes, et le serveur
    /// reste l'autorité — notamment pour le cas multi-appareil, que cette valeur
    /// ne peut pas connaître.
    private(set) var lastSubmissionAt: Date?

    /// **Propage.** Le `try?` qui enveloppait cet appel côté carte rendait les
    /// cinq refus de l'Edge Function indiscernables du succès.
    func submit(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        try await functions.submitContribution(category: category, title: title, position: position, languageCode: languageCode)
        lastSubmissionAt = Date()
    }

    /// Échoue en silence, délibérément : sans mes votes, les deux sections du
    /// volet retombent sur « tout à découvrir », ce qui est dégradé mais juste.
    /// Une alerte pour ça interromprait la lecture sans rien offrir à faire.
    func loadMyVotes(uid: String) async {
        myVotes = (try? await repository.fetchMyVotes(uid: uid)) ?? [:]
    }

    func vote(on spot: Contribution, direction: VoteDirection) async {
        guard let counts = try? await functions.castVote(spotId: spot.id, direction: direction) else { return }
        // Enregistré AVANT la mise à jour des compteurs : le spot peut ne plus
        // être dans `approvedSpots` (fragment reconstruit entre-temps), et mon
        // vote a bien eu lieu quoi qu'il arrive. L'ordre inverse le perdrait sur
        // le `guard` suivant.
        myVotes[spot.id] = direction
        guard let index = approvedSpots.firstIndex(where: { $0.id == spot.id }) else { return }
        approvedSpots[index].upvotes = counts.upvotes
        approvedSpots[index].downvotes = counts.downvotes
    }

    func report(_ spot: Contribution, reason: String?) async {
        try? await functions.reportContribution(spotId: spot.id, reason: reason)
    }

    func block(authorUid: String, handle: String? = nil) {
        guard !blockedAuthorUIDs.contains(authorUid) else { return }
        modelContext.insert(BlockedContributor(authorUid: authorUid, handle: handle))
        blockedAuthorUIDs.insert(authorUid)
        try? modelContext.save()
    }

    /// Les contributeurs masqués avec le pseudo qu'ils portaient au blocage.
    /// Les réglages affichaient jusqu'ici l'UUID brut, donc illisible.
    ///
    /// Une structure et pas un tuple : Swift n'a pas de `KeyPath` vers un
    /// élément de tuple, donc `ForEach(…, id: \.uid)` ne compilerait pas.
    var blockedContributors: [BlockedContributorSummary] {
        let rows = (try? modelContext.fetch(FetchDescriptor<BlockedContributor>())) ?? []
        return rows
            .sorted { $0.blockedAt > $1.blockedAt }
            .map { BlockedContributorSummary(uid: $0.authorUid, handle: $0.authorHandle) }
    }

    func unblock(authorUid: String) {
        let descriptor = FetchDescriptor<BlockedContributor>(predicate: #Predicate { $0.authorUid == authorUid })
        guard let existing = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(existing)
        blockedAuthorUIDs.remove(authorUid)
        try? modelContext.save()
    }
}

/// Une ligne de la liste des contributeurs masqués, prête à afficher.
struct BlockedContributorSummary: Identifiable, Equatable, Sendable {
    var id: String { uid }
    let uid: String
    let handle: String?
}
