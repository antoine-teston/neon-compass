import Foundation

enum CommunityPlatform: String, Codable, Sendable, CaseIterable, Identifiable {
    case ps5, xbox, pc
    case crossPlatform = "cross-platform"

    var id: String { rawValue }

    var localizationKey: String { "social.communities.platform.\(rawValue)" }
}

enum CommunityPlaystyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case rp, racing, heists, casual, competitive, exploration, creative

    var id: String { rawValue }

    var localizationKey: String { "social.communities.playstyle.\(rawValue)" }
}

struct PlayerCommunity: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let ownerID: String
    let name: String
    let platform: CommunityPlatform
    let playstyles: [CommunityPlaystyle]
    let languages: [String]
    let discordInvite: String?
    let memberCount: Int
    let serverAddress: String?
    let promoted: Bool
    let promotedUntil: String?
    let createdAt: String
    let updatedAt: String

    var isPromoted: Bool { promoted }

    static func memberBracket(for count: Int) -> String {
        switch count {
        case 500...: "500+"
        case 100...: "100+"
        case 50...: "50+"
        case 10...: "10+"
        default: "\(count)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case name, platform, playstyles, languages
        case discordInvite = "discord_invite"
        case memberCount = "member_count"
        case serverAddress = "server_address"
        case promoted
        case promotedUntil = "promoted_until"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
