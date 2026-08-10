import Foundation

enum CommunityEventType: String, Codable, Sendable, CaseIterable, Identifiable {
    case tournament
    case themedNight = "themed_night"
    case recruitment
    case launch
    case training
    case other

    var id: String { rawValue }

    var localizationKey: String { "social.communities.eventType.\(rawValue)" }

    var systemImage: String {
        switch self {
        case .tournament: "trophy"
        case .themedNight: "moon.stars"
        case .recruitment: "person.badge.plus"
        case .launch: "party.popper"
        case .training: "figure.run"
        case .other: "calendar"
        }
    }
}

struct CommunityEvent: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let communityID: String
    let eventType: CommunityEventType
    let platform: CommunityPlatform
    let startsAt: String
    let endsAt: String?
    let slots: Int?
    let createdAt: String

    var startsAtDate: Date? { Contribution.parseTimestamp(startsAt) }
    var endsAtDate: Date? { Contribution.parseTimestamp(endsAt) }

    enum CodingKeys: String, CodingKey {
        case id
        case communityID = "community_id"
        case eventType = "event_type"
        case platform
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case slots
        case createdAt = "created_at"
    }
}
