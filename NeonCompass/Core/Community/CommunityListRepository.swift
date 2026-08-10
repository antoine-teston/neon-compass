import Foundation

protocol CommunityListRepository: Sendable {
    func fetchAll() async throws -> [PlayerCommunity]
    func fetchUpcomingEvents() async throws -> [CommunityEvent]
    func createCommunity(_ draft: PlayerCommunityDraft) async throws -> PlayerCommunity
    func updateCommunity(id: String, draft: PlayerCommunityDraft) async throws
    func deleteCommunity(id: String) async throws
    func createEvent(_ draft: CommunityEventDraft, communityID: String) async throws
    func deleteEvent(id: String) async throws
}

struct PlayerCommunityDraft: Encodable, Sendable {
    let name: String
    let platform: CommunityPlatform
    let playstyles: [CommunityPlaystyle]
    let languages: [String]
    let discordInvite: String?
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case name, platform, playstyles, languages
        case discordInvite = "discord_invite"
        case memberCount = "member_count"
    }
}

struct CommunityEventDraft: Encodable, Sendable {
    let eventType: CommunityEventType
    let platform: CommunityPlatform
    let startsAt: String
    let endsAt: String?
    let slots: Int?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case platform
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case slots
    }
}

enum CommunityListError: Error {
    case notConfigured
}
