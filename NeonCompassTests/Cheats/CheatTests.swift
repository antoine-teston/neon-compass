import Testing
import Foundation
@testable import NeonCompass

struct CheatTests {
    @Test func decodesCheatIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "cheat_sample_placeholder",
            "category": "misc",
            "effect": {"en": "Sample cheat", "fr": "Cheat exemple"},
            "sequence": {"ps5": ["up", "up", "circle", "l1"], "xbox": ["up", "up", "b", "l1"]},
            "blocksTrophies": true,
            "status": "draft",
            "verifiedBy": ["internal:fixture"]
        }
        """.utf8)
        let cheat = try JSONDecoder().decode(Cheat.self, from: json)
        #expect(cheat.id == "cheat_sample_placeholder")
        #expect(cheat.category == .misc)
        #expect(cheat.blocksTrophies)
        #expect(cheat.sequence[.ps5] == [.up, .up, .circle, .l1])
        #expect(cheat.sequence[.xbox] == [.up, .up, .b, .l1])
        #expect(cheat.effect.resolved(for: "fr") == "Cheat exemple")
    }
}
