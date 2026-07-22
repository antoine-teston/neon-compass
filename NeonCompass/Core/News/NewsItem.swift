import Foundation

enum NewsCategory: String, CaseIterable, Codable, Sendable {
    case announcement, patch, event
}

struct NewsItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: NewsCategory
    let title: LocalizedText
    let body: LocalizedText
    let publishedAt: String
}
