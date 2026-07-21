import Foundation
import SwiftData

/// Marqueur strictement local — distinct de la contribution communautaire
/// (spec §5), qui requiert un compte et arrive au plan 5.
@Model
final class PersonalPin: Identifiable {
    var id: UUID
    var x: Double
    var y: Double
    var title: String
    var createdAt: Date

    init(id: UUID = UUID(), x: Double, y: Double, title: String, createdAt: Date = .now) {
        self.id = id
        self.x = x
        self.y = y
        self.title = title
        self.createdAt = createdAt
    }
}
