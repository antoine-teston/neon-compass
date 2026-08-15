import Testing
import Foundation
@testable import NeonCompass

struct OnlineEventHighlightsTests {
    private func event(_ body: String) throws -> OnlineEvent {
        try JSONDecoder().decode(OnlineEvent.self, from: Data("""
        {
          "id": "online_test", "game": "gtav",
          "startsAt": "2026-08-13T09:00:00Z", "endsAt": "2026-08-20T09:00:00Z",
          "title": { "en": "t" }\(body.isEmpty ? "" : ",")
          \(body)
        }
        """.utf8))
    }

    /// « 3× » bat « +15 % » : une prime en pourcentage se compare ramenée à un
    /// facteur — la règle qui vivait en privé dans la carte.
    @Test func bestBonusComparesMultipliersAndPercents() throws {
        let event = try self.event("""
        "bonuses": [
          { "activity": { "en": "small" }, "percentBonus": 15, "includesRP": false },
          { "activity": { "en": "big" }, "multiplier": 3, "includesRP": false }
        ]
        """)
        let highlights = OnlineEventHighlights.compute(for: event, languageCode: "en")
        #expect(highlights.first?.name == "big")
    }

    @Test func bestDiscountIsTheLargestPercent() throws {
        let event = try self.event("""
        "discounts": [
          { "item": { "en": "cheap" }, "percent": 10 },
          { "item": { "en": "deep" }, "percent": 40 }
        ]
        """)
        let highlights = OnlineEventHighlights.compute(for: event, languageCode: "en")
        #expect(highlights.contains { $0.name == "deep" })
        #expect(!highlights.contains { $0.name == "cheap" })
    }

    @Test func emptyEventHasNoHighlights() throws {
        #expect(try OnlineEventHighlights.compute(for: event(""), languageCode: "en").isEmpty)
    }

    /// Le « +N » du héro : tout ce que la carte compacte ne montre pas —
    /// bonus + remises + récompenses + podium, moins ce qui est déjà affiché.
    @Test func hiddenCountCountsEverythingBeyondShown() throws {
        let event = try self.event("""
        "bonuses": [ { "activity": { "en": "a" }, "multiplier": 2, "includesRP": false } ],
        "discounts": [ { "item": { "en": "b" }, "percent": 30 }, { "item": { "en": "c" }, "percent": 10 } ],
        "rewards": [ { "kind": "vehicle", "item": { "en": "d" } } ],
        "podiumVehicle": { "en": "e" }
        """)
        // 1 bonus + 2 remises + 1 récompense + 1 podium = 5 entrées ; 2 affichées.
        #expect(OnlineEventHighlights.hiddenCount(for: event, shown: 2) == 3)
        #expect(OnlineEventHighlights.hiddenCount(for: event, shown: 5) == 0)
        #expect(OnlineEventHighlights.hiddenCount(for: event, shown: 9) == 0)
    }
}
