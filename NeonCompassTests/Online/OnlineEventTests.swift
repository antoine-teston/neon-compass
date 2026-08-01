import Testing
import Foundation
@testable import NeonCompass

struct OnlineEventTests {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func json(startsAt: String = "2026-08-06T09:00:00Z", endsAt: String = "2026-08-13T09:00:00Z") -> Data {
        Data("""
        {
          "id": "online_gtav_abc123",
          "game": "gtav",
          "startsAt": "\(startsAt)",
          "endsAt": "\(endsAt)",
          "title": { "en": "Weekly update", "fr": "Mise à jour de la semaine" },
          "bonuses": [{ "activity": { "en": "Sea races" }, "label": { "en": "Double payouts" } }],
          "discounts": [{ "item": { "en": "Speedboat" }, "percent": 30 }],
          "podiumVehicle": { "en": "Coupé" },
          "status": "published",
          "sources": ["https://example.test/x"],
          "confidence": "multi-source"
        }
        """.utf8)
    }

    @Test func decodesEveryField() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.id == "online_gtav_abc123")
        #expect(event.game == .reference)
        #expect(event.endsAt == date("2026-08-13T09:00:00Z"))
        #expect(event.bonuses.count == 1)
        #expect(event.discounts.first?.percent == 30)
        #expect(event.podiumVehicle?.resolved(for: "en") == "Coupé")
    }

    /// `sources` et `status` sont pipeline-only : Codable ignore les clés
    /// inconnues, et les URL contiennent les marques — les embarquer mettrait à
    /// l'écran exactement ce que la politique stricte évite.
    @Test func decodingIgnoresPipelineOnlyFields() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.title.resolved(for: "fr") == "Mise à jour de la semaine")
    }

    /// Les listes absentes valent liste vide, jamais un échec de décodage : le
    /// schéma ne les exige pas.
    @Test func absentListsDecodeAsEmpty() throws {
        let minimal = Data("""
        {
          "id": "online_gtav_min",
          "game": "gtav",
          "startsAt": "2026-08-06T09:00:00Z",
          "endsAt": "2026-08-13T09:00:00Z",
          "title": { "en": "Minimal" },
          "status": "published",
          "sources": ["https://example.test/x"],
          "confidence": "multi-source"
        }
        """.utf8)
        let event = try JSONDecoder().decode(OnlineEvent.self, from: minimal)
        #expect(event.bonuses.isEmpty)
        #expect(event.discounts.isEmpty)
        #expect(event.podiumVehicle == nil)
    }

    @Test func isActiveInsideTheWindow() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.isActive(at: date("2026-08-10T00:00:00Z")))
    }

    @Test func isNotActiveBeforeOrAfter() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(!event.isActive(at: date("2026-08-05T00:00:00Z")))
        #expect(!event.isActive(at: date("2026-08-14T00:00:00Z")))
    }

    /// La borne de fin est exclusive : à `endsAt` pile, c'est terminé.
    @Test func endBoundIsExclusive() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(!event.isActive(at: date("2026-08-13T09:00:00Z")))
    }

    @Test func remainingIsTheDistanceToTheEnd() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.remaining(at: date("2026-08-12T09:00:00Z")) == 86_400)
    }

    /// JAMAIS un compte à rebours négatif : un événement terminé rend nil, et
    /// la vue affiche « terminé » au lieu de « il reste -3 jours ».
    @Test func remainingIsNilOnceOver() throws {
        let event = try JSONDecoder().decode(OnlineEvent.self, from: json())
        #expect(event.remaining(at: date("2026-08-14T00:00:00Z")) == nil)
    }
}
