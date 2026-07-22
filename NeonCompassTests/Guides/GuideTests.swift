import Testing
import Foundation
@testable import NeonCompass

struct GuideTests {
    @Test func decodesGuideIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "guide_getting_started",
            "chapter": "beginner",
            "title": {"en": "Getting Started", "fr": "Premiers pas"},
            "body": {"en": "# Welcome\\n\\nThis is a sample guide."},
            "status": "draft"
        }
        """.utf8)
        let guide = try JSONDecoder().decode(Guide.self, from: json)
        #expect(guide.id == "guide_getting_started")
        #expect(guide.chapter == .beginner)
        #expect(guide.title.resolved(for: "fr") == "Premiers pas")
        #expect(guide.body.en.contains("Welcome"))
    }
}
