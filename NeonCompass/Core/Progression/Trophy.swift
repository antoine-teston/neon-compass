import Foundation

struct Trophy: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: LocalizedText
    let note: LocalizedText?
}
