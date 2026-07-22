import Foundation

enum GuideChapter: String, CaseIterable, Codable, Sendable {
    case story, sideContent, beginner, money
}

/// Champs pipeline-only du schéma (`status`) ignorés au décodage — même
/// stratégie que POI (plan 2) et Cheat (plan 3b).
struct Guide: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let chapter: GuideChapter
    let title: LocalizedText
    let body: LocalizedText
}
