import Testing
@testable import NeonCompass

@MainActor
struct FeedModelTests {
    private func sampleItem(id: String, publishedAt: String) -> NewsItem {
        NewsItem(
            id: id,
            category: .announcement,
            title: LocalizedText(en: "Title \(id)", fr: nil, es: nil, it: nil, de: nil),
            body: LocalizedText(en: "Body \(id)", fr: nil, es: nil, it: nil, de: nil),
            publishedAt: publishedAt
        )
    }

    @Test func sortsNewsItemsByMostRecentFirst() {
        let older = sampleItem(id: "a", publishedAt: "2026-07-01")
        let newer = sampleItem(id: "b", publishedAt: "2026-07-20")
        let model = FeedModel(newsItems: [older, newer])
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }

    @Test func updateNewsItemsReplacesContentAndResorts() {
        let model = FeedModel(newsItems: [])
        let older = sampleItem(id: "a", publishedAt: "2026-07-01")
        let newer = sampleItem(id: "b", publishedAt: "2026-07-20")
        model.updateNewsItems([older, newer])
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }
}
