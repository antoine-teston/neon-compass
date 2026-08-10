import Foundation
import Observation

@Observable
@MainActor
final class CommunitiesModel {
    var communities: [PlayerCommunity] = []
    var upcomingEvents: [CommunityEvent] = []
    var platformFilter: CommunityPlatform?
    var playstyleFilter: CommunityPlaystyle?

    private let repository: any CommunityListRepository

    init(repository: any CommunityListRepository = SupabaseCommunityListRepository()) {
        self.repository = repository
    }

    var promotedCommunities: [PlayerCommunity] {
        communities.filter(\.isPromoted)
    }

    var filteredCommunities: [PlayerCommunity] {
        communities.filter { community in
            if let pf = platformFilter, community.platform != pf { return false }
            if let sf = playstyleFilter, !community.playstyles.contains(sf) { return false }
            return true
        }
    }

    func load() async {
        communities = (try? await repository.fetchAll()) ?? []
        upcomingEvents = (try? await repository.fetchUpcomingEvents()) ?? []
    }

    func createCommunity(_ draft: PlayerCommunityDraft) async throws {
        let created = try await repository.createCommunity(draft)
        communities.insert(created, at: 0)
    }

    func deleteCommunity(id: String) async throws {
        try await repository.deleteCommunity(id: id)
        communities.removeAll { $0.id == id }
    }

    func createEvent(_ draft: CommunityEventDraft, communityID: String) async throws {
        try await repository.createEvent(draft, communityID: communityID)
        upcomingEvents = (try? await repository.fetchUpcomingEvents()) ?? []
    }

    func deleteEvent(id: String) async throws {
        try await repository.deleteEvent(id: id)
        upcomingEvents.removeAll { $0.id == id }
    }
}
