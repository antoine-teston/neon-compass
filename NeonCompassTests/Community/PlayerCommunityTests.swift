import Testing
import Foundation
@testable import NeonCompass

struct PlayerCommunityTests {
    @Test func decodesFromSupabaseJSON() throws {
        let json = """
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "owner_id": "660e8400-e29b-41d4-a716-446655440000",
          "name": "Neon Riders",
          "platform": "ps5",
          "playstyles": ["racing", "casual"],
          "languages": ["fr", "en"],
          "discord_invite": "https://discord.gg/abc123",
          "member_count": 42,
          "server_address": null,
          "promoted": true,
          "promoted_until": "2026-09-10T00:00:00+00:00",
          "created_at": "2026-08-10T12:00:00+00:00",
          "updated_at": "2026-08-10T12:00:00+00:00"
        }
        """.data(using: .utf8)!
        let community = try JSONDecoder().decode(PlayerCommunity.self, from: json)
        #expect(community.name == "Neon Riders")
        #expect(community.platform == .ps5)
        #expect(community.playstyles == [.racing, .casual])
        #expect(community.isPromoted)
        #expect(community.discordInvite == "https://discord.gg/abc123")
    }

    @Test func memberCountBracketRoundsDown() {
        #expect(PlayerCommunity.memberBracket(for: 1) == "1")
        #expect(PlayerCommunity.memberBracket(for: 9) == "9")
        #expect(PlayerCommunity.memberBracket(for: 10) == "10+")
        #expect(PlayerCommunity.memberBracket(for: 49) == "10+")
        #expect(PlayerCommunity.memberBracket(for: 50) == "50+")
        #expect(PlayerCommunity.memberBracket(for: 100) == "100+")
        #expect(PlayerCommunity.memberBracket(for: 500) == "500+")
        #expect(PlayerCommunity.memberBracket(for: 1000) == "500+")
    }

    @Test func unpromotedCommunityIsNotPromoted() throws {
        let json = """
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "owner_id": "660e8400-e29b-41d4-a716-446655440000",
          "name": "Chill Squad",
          "platform": "xbox",
          "playstyles": ["casual"],
          "languages": ["en"],
          "discord_invite": null,
          "member_count": 5,
          "server_address": null,
          "promoted": false,
          "promoted_until": null,
          "created_at": "2026-08-10T12:00:00+00:00",
          "updated_at": "2026-08-10T12:00:00+00:00"
        }
        """.data(using: .utf8)!
        let community = try JSONDecoder().decode(PlayerCommunity.self, from: json)
        #expect(!community.isPromoted)
    }

    @Test func crossPlatformDecodes() throws {
        let json = """
        {
          "id": "a", "owner_id": "b", "name": "Global",
          "platform": "cross-platform",
          "playstyles": ["rp"], "languages": ["en"],
          "discord_invite": null, "member_count": 1,
          "server_address": null, "promoted": false,
          "promoted_until": null,
          "created_at": "2026-08-10T00:00:00Z",
          "updated_at": "2026-08-10T00:00:00Z"
        }
        """.data(using: .utf8)!
        let community = try JSONDecoder().decode(PlayerCommunity.self, from: json)
        #expect(community.platform == .crossPlatform)
    }
}
