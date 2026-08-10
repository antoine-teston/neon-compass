import Testing
import Foundation
@testable import NeonCompass

struct CommunityEventTests {
    @Test func decodesFromSupabaseJSON() throws {
        let json = """
        {
          "id": "770e8400-e29b-41d4-a716-446655440000",
          "community_id": "550e8400-e29b-41d4-a716-446655440000",
          "event_type": "tournament",
          "platform": "ps5",
          "starts_at": "2026-08-15T20:00:00+00:00",
          "ends_at": "2026-08-15T23:00:00+00:00",
          "slots": 16,
          "created_at": "2026-08-10T12:00:00+00:00"
        }
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(CommunityEvent.self, from: json)
        #expect(event.eventType == .tournament)
        #expect(event.slots == 16)
        #expect(event.communityID == "550e8400-e29b-41d4-a716-446655440000")
    }

    @Test func eventWithoutEndDateDecodes() throws {
        let json = """
        {
          "id": "770e8400-e29b-41d4-a716-446655440000",
          "community_id": "550e8400-e29b-41d4-a716-446655440000",
          "event_type": "recruitment",
          "platform": "cross-platform",
          "starts_at": "2026-08-15T20:00:00+00:00",
          "ends_at": null,
          "slots": null,
          "created_at": "2026-08-10T12:00:00+00:00"
        }
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(CommunityEvent.self, from: json)
        #expect(event.endsAt == nil)
        #expect(event.slots == nil)
        #expect(event.eventType == .recruitment)
    }

    @Test func themedNightDecodes() throws {
        let json = """
        {
          "id": "a", "community_id": "b",
          "event_type": "themed_night",
          "platform": "xbox",
          "starts_at": "2026-08-15T20:00:00+00:00",
          "ends_at": null, "slots": null,
          "created_at": "2026-08-10T00:00:00Z"
        }
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(CommunityEvent.self, from: json)
        #expect(event.eventType == .themedNight)
    }

    @Test func startsAtDateParses() throws {
        let json = """
        {
          "id": "a", "community_id": "b",
          "event_type": "training",
          "platform": "pc",
          "starts_at": "2026-08-15T20:00:00+00:00",
          "ends_at": null, "slots": null,
          "created_at": "2026-08-10T00:00:00Z"
        }
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(CommunityEvent.self, from: json)
        #expect(event.startsAtDate != nil)
    }
}
