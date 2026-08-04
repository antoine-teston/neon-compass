import Foundation
import Testing
@testable import NeonCompass

struct ContributionTests {
    private func decode(_ json: String) throws -> Contribution {
        try JSONDecoder().decode(Contribution.self, from: Data(json.utf8))
    }

    private static let base = """
    {"id":"c1","authorUid":"u1","authorHandle":"NEON-FALCON-88","category":"landmark",
     "title":"Toit du parking","languageCode":"fr","position":{"x":0.3,"y":0.6},
     "status":"approved","upvotes":12,"downvotes":1
    """

    @Test func decodesTheApprovalTimestamp() throws {
        let spot = try decode(Self.base + ###","approvedAt":"2026-08-04T18:00:00Z"}"###)
        #expect(spot.approvedAt == "2026-08-04T18:00:00Z")
        let date = try #require(spot.approvedAtDate)
        #expect(abs(date.timeIntervalSince1970 - 1_785_866_400) < 1)
    }

    /// LE cas qui compte. Un fragment mis en cache AVANT ce changement n'a pas
    /// la clé. Rendre le champ obligatoire ferait échouer le décodage de tout
    /// le fragment, donc viderait la carte hors ligne.
    @Test func decodesWithoutTheTimestamp() throws {
        let spot = try decode(Self.base + "}")
        #expect(spot.approvedAt == nil)
        #expect(spot.approvedAtDate == nil)
    }

    /// Une date illisible est ignorée, pas fatale — même règle que
    /// `OnlineEventBonus.until`. La perdre range la proposition en fin de
    /// section ; elle ne casse rien.
    @Test func anUnparsableTimestampIsIgnoredNotFatal() throws {
        let spot = try decode(Self.base + ###","approvedAt":"pas une date"}"###)
        #expect(spot.approvedAt == "pas une date")
        #expect(spot.approvedAtDate == nil)
    }

    /// Le fragment publié par `rebuild-community-bundles` porte des fractions
    /// de seconde et un décalage explicite : Postgres sérialise ainsi.
    @Test func decodesPostgresFractionalTimestamps() throws {
        let spot = try decode(Self.base + ###","approvedAt":"2026-08-04T18:00:00.123456+00:00"}"###)
        #expect(spot.approvedAtDate != nil)
    }

    /// Un aller-retour complet : le cache SwiftData réencode ce qu'il a décodé.
    @Test func roundTripsThroughEncoding() throws {
        let spot = try decode(Self.base + ###","approvedAt":"2026-08-04T18:00:00Z"}"###)
        let reencoded = try JSONEncoder().encode(spot)
        let again = try JSONDecoder().decode(Contribution.self, from: reencoded)
        #expect(again == spot)
    }
}
