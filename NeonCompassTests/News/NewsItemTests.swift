import Testing
import Foundation
@testable import NeonCompass

struct NewsItemTests {
    @Test func decodesNewsItemIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "news_sample_patch",
            "category": "patch",
            "title": {"en": "Title update 1.1", "fr": "Mise à jour 1.1"},
            "body": {"en": "Sample patch notes, reworded in our own words."},
            "publishedAt": "2026-07-20",
            "status": "draft",
            "sources": ["internal:fixture"]
        }
        """.utf8)
        let newsItem = try JSONDecoder().decode(NewsItem.self, from: json)
        #expect(newsItem.id == "news_sample_patch")
        #expect(newsItem.category == .patch)
        #expect(newsItem.title.resolved(for: "fr") == "Mise à jour 1.1")
        #expect(newsItem.publishedAt == "2026-07-20")
    }
}
