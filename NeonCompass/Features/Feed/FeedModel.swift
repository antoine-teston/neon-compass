import Foundation
import Observation

@Observable
@MainActor
final class FeedModel {
    private(set) var newsItems: [NewsItem]

    init(newsItems: [NewsItem]) {
        self.newsItems = Self.sortedByMostRecent(newsItems)
    }

    func updateNewsItems(_ newItems: [NewsItem]) {
        newsItems = Self.sortedByMostRecent(newItems)
    }

    private static func sortedByMostRecent(_ items: [NewsItem]) -> [NewsItem] {
        items.sorted { $0.publishedAt > $1.publishedAt }
    }
}
