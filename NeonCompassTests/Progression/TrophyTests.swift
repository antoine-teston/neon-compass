import Testing
import Foundation
@testable import NeonCompass

struct TrophyTests {
    @Test func decodesTrophyIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "trophy_sample_completionist",
            "title": {"en": "Sample Completionist", "fr": "Complétiste (exemple)"},
            "note": {"en": "Sample trophy fixture, not a confirmed GTA VI trophy."},
            "status": "draft",
            "sources": ["internal:fixture"]
        }
        """.utf8)
        let trophy = try JSONDecoder().decode(Trophy.self, from: json)
        #expect(trophy.id == "trophy_sample_completionist")
        #expect(trophy.title.resolved(for: "fr") == "Complétiste (exemple)")
        #expect(trophy.note?.en.contains("Sample trophy") == true)
    }
}
