import Testing
import Foundation
@testable import NeonCompass

@MainActor
struct CommunitiesModelTests {
    private func community(
        id: String = "a",
        name: String = "Test",
        platform: CommunityPlatform = .ps5,
        playstyles: [CommunityPlaystyle] = [.casual],
        promoted: Bool = false,
        memberCount: Int = 10
    ) -> PlayerCommunity {
        PlayerCommunity(
            id: id, ownerID: "owner", name: name, platform: platform,
            playstyles: playstyles, languages: ["en"],
            discordInvite: nil, memberCount: memberCount,
            serverAddress: nil, promoted: promoted, promotedUntil: nil,
            createdAt: "2026-08-10T00:00:00Z", updatedAt: "2026-08-10T00:00:00Z"
        )
    }

    @Test func promotedCommunitiesAreFiltered() {
        let all = [
            community(id: "a", promoted: true),
            community(id: "b", promoted: false),
            community(id: "c", promoted: true),
        ]
        let model = CommunitiesModel(repository: FakeCommunityRepository(communities: all))
        model.communities = all
        #expect(model.promotedCommunities.count == 2)
    }

    @Test func filterByPlatformWorks() {
        let all = [
            community(id: "a", platform: .ps5),
            community(id: "b", platform: .xbox),
            community(id: "c", platform: .ps5),
        ]
        let model = CommunitiesModel(repository: FakeCommunityRepository(communities: all))
        model.communities = all
        model.platformFilter = .ps5
        #expect(model.filteredCommunities.count == 2)
    }

    @Test func filterByPlaystyleWorks() {
        let all = [
            community(id: "a", playstyles: [.racing, .casual]),
            community(id: "b", playstyles: [.rp]),
            community(id: "c", playstyles: [.casual]),
        ]
        let model = CommunitiesModel(repository: FakeCommunityRepository(communities: all))
        model.communities = all
        model.playstyleFilter = .casual
        #expect(model.filteredCommunities.count == 2)
    }

    @Test func noFilterShowsAll() {
        let all = [community(id: "a"), community(id: "b")]
        let model = CommunitiesModel(repository: FakeCommunityRepository(communities: all))
        model.communities = all
        #expect(model.filteredCommunities.count == 2)
    }
}

final class FakeCommunityRepository: CommunityListRepository, @unchecked Sendable {
    var communities: [PlayerCommunity]
    var events: [CommunityEvent]

    init(communities: [PlayerCommunity] = [], events: [CommunityEvent] = []) {
        self.communities = communities
        self.events = events
    }

    func fetchAll() async throws -> [PlayerCommunity] { communities }
    func fetchUpcomingEvents() async throws -> [CommunityEvent] { events }
    func createCommunity(_ draft: PlayerCommunityDraft) async throws -> PlayerCommunity {
        fatalError("not tested here")
    }
    func updateCommunity(id: String, draft: PlayerCommunityDraft) async throws {}
    func deleteCommunity(id: String) async throws {}
    func createEvent(_ draft: CommunityEventDraft, communityID: String) async throws {}
    func deleteEvent(id: String) async throws {}
}
