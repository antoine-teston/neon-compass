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

    init(
        repository: ContributionRepository,
        functions: ContributionFunctionsCalling,
        gateProvider: CommunityGateProviding,
        modelContext: ModelContext
    ) {
        self.repository = repository
        self.functions = functions
        self.gateProvider = gateProvider
        self.modelContext = modelContext
        self.blockedAuthorUIDs = []
        self.refreshBlockedAuthors()
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

    func loadApprovedSpots() async {
        approvedSpots = (try? await repository.fetchApproved()) ?? []
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
