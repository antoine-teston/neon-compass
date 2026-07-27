import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CommunityModel {
    private(set) var approvedSpots: [Contribution] = []
    private(set) var myContributions: [Contribution] = []
    private(set) var blockedAuthorUIDs: Set<String>
    private(set) var contributionsEnabled = true

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
    }

    /// Câblage de production, en un seul endroit : les deux écrans qui
    /// construisent un `CommunityModel` (carte et profil) passaient sinon la même
    /// liste de dépendances, et le nom de collection des fragments s'y serait
    /// dupliqué.
    static func live(modelContext: ModelContext) -> CommunityModel {
        let collectionName = CommunityBundleVersionProvider.collectionName
        return CommunityModel(
            repository: FirestoreContributionRepository(),
            functions: FirebaseContributionFunctions(),
            gateProvider: RemoteConfigCommunityGateProvider(),
            modelContext: modelContext,
            approvedStore: ContentStore<Contribution>(
                collectionName: collectionName,
                remote: ChunkedContentRepository<Contribution>(collectionName: collectionName),
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

    var visibleSpots: [Contribution] {
        approvedSpots.filter { spot in
            guard let authorUid = spot.authorUid else { return true }
            return !blockedAuthorUIDs.contains(authorUid)
        }
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

    func submit(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        try await functions.submitContribution(category: category, title: title, position: position, languageCode: languageCode)
    }

    func vote(on spot: Contribution, direction: VoteDirection) async {
        guard let counts = try? await functions.castVote(spotId: spot.id, direction: direction) else { return }
        guard let index = approvedSpots.firstIndex(where: { $0.id == spot.id }) else { return }
        approvedSpots[index].upvotes = counts.upvotes
        approvedSpots[index].downvotes = counts.downvotes
    }

    func report(_ spot: Contribution, reason: String?) async {
        try? await functions.reportContribution(spotId: spot.id, reason: reason)
    }

    func isBlocked(authorUid: String) -> Bool {
        blockedAuthorUIDs.contains(authorUid)
    }

    func block(authorUid: String) {
        guard !blockedAuthorUIDs.contains(authorUid) else { return }
        modelContext.insert(BlockedContributor(authorUid: authorUid))
        blockedAuthorUIDs.insert(authorUid)
        try? modelContext.save()
    }

    func unblock(authorUid: String) {
        let descriptor = FetchDescriptor<BlockedContributor>(predicate: #Predicate { $0.authorUid == authorUid })
        guard let existing = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(existing)
        blockedAuthorUIDs.remove(authorUid)
        try? modelContext.save()
    }
}
