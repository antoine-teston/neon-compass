import Testing
import Foundation
@testable import NeonCompass

struct LeaderboardTests {
    @Test func decodesRows() throws {
        let json = Data("""
        { "rows": [
          { "uid": "u1", "handle": "NEON-FALCON-88", "xp": 300, "approvedCount": 12 },
          { "uid": "u2", "handle": "VIOLET-HAWK-04", "xp": 100, "approvedCount": 3 }
        ] }
        """.utf8)
        let board = try JSONDecoder().decode(Leaderboard.self, from: json)
        #expect(board.rows.count == 2)
        #expect(board.rows.first?.handle == "NEON-FALCON-88")
        #expect(board.rows.first?.id == "u1")
    }

    /// Un classement vide n'est pas une erreur : c'est ce que rend la première
    /// exécution, avant qu'aucune contribution n'ait été approuvée.
    @Test func emptyBoardDecodes() throws {
        let board = try JSONDecoder().decode(Leaderboard.self, from: Data(#"{ "rows": [] }"#.utf8))
        #expect(board.rows.isEmpty)
    }

    /// `rank` est déposé par la Function planifiée : il est absent tant qu'elle
    /// n'a pas tourné, et le Profil n'affiche alors pas de ligne de rang.
    @Test func profileDecodesWithoutRank() throws {
        let json = Data("""
        { "handle": "NEON-FALCON-88", "xp": 300, "level": 4, "isPremium": false }
        """.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.rank == nil)
    }

    @Test func profileDecodesWithRank() throws {
        let json = Data("""
        { "handle": "NEON-FALCON-88", "xp": 300, "level": 4, "isPremium": false, "rank": 342 }
        """.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.rank == 342)
    }
}
