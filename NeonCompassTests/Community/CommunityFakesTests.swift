import SwiftData
import Testing
@testable import NeonCompass

final class FakeContributionRepository: ContributionRepository {
    nonisolated(unsafe) var approvedToReturn: [Contribution] = []
    nonisolated(unsafe) var mineToReturn: [Contribution] = []

    func fetchApproved() async throws -> [Contribution] { approvedToReturn }
    func fetchMine(uid: String) async throws -> [Contribution] { mineToReturn }
}

final class FakeContributionFunctions: ContributionFunctionsCalling {
    nonisolated(unsafe) private(set) var submitCallCount = 0
    nonisolated(unsafe) private(set) var lastVote: (spotId: String, direction: VoteDirection)?
    nonisolated(unsafe) private(set) var lastReport: (spotId: String, reason: String?)?

    func submitContribution(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        submitCallCount += 1
    }

    nonisolated(unsafe) var voteResultToReturn: (upvotes: Int, downvotes: Int) = (0, 0)

    func castVote(spotId: String, direction: VoteDirection) async throws -> (upvotes: Int, downvotes: Int) {
        lastVote = (spotId, direction)
        return voteResultToReturn
    }

    func reportContribution(spotId: String, reason: String?) async throws {
        lastReport = (spotId, reason)
    }
}

private func makeSpot(id: String, authorUid: String?) -> Contribution {
    Contribution(
        id: id,
        authorUid: authorUid,
        authorHandle: "NEON-FALCON-88",
        category: .landmark,
        title: "A great spot",
        languageCode: "en",
        position: NormalizedPoint(x: 0.5, y: 0.5),
        status: .approved,
        upvotes: 0,
        downvotes: 0
    )
}

@MainActor
struct CommunityFakesTests {
    @Test func visibleSpotsExcludesBlockedAuthors() async throws {
        let repository = FakeContributionRepository()
        repository.approvedToReturn = [makeSpot(id: "1", authorUid: "author-a"), makeSpot(id: "2", authorUid: "author-b")]
        let container = try ModelContainer(for: BlockedContributor.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CommunityModel(repository: repository, functions: FakeContributionFunctions(), modelContext: ModelContext(container))

        await model.loadApprovedSpots()
        model.block(authorUid: "author-a")

        #expect(model.visibleSpots.map(\.id) == ["2"])
    }

    @Test func voteCallsCastVoteWithSpotIDAndDirection() async throws {
        let functions = FakeContributionFunctions()
        let container = try ModelContainer(for: BlockedContributor.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CommunityModel(repository: FakeContributionRepository(), functions: functions, modelContext: ModelContext(container))
        let spot = makeSpot(id: "spot-1", authorUid: "author-a")

        await model.vote(on: spot, direction: .up)

        #expect(functions.lastVote?.spotId == "spot-1")
        #expect(functions.lastVote?.direction == .up)
    }

    @Test func blockThenUnblockRestoresVisibility() throws {
        let container = try ModelContainer(for: BlockedContributor.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CommunityModel(repository: FakeContributionRepository(), functions: FakeContributionFunctions(), modelContext: ModelContext(container))

        model.block(authorUid: "author-a")
        #expect(model.isBlocked(authorUid: "author-a"))

        model.unblock(authorUid: "author-a")
        #expect(!model.isBlocked(authorUid: "author-a"))
    }
}
