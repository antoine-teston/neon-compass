import Foundation
import SwiftData

/// Source de vérité unique carte↔checklists (spec §5, réutilisée au plan 4).
@Model
final class FoundEntry {
    @Attribute(.unique) var poiID: String
    var foundAt: Date
    var updatedAt: Date = Date.now

    init(poiID: String, foundAt: Date = .now, updatedAt: Date = .now) {
        self.poiID = poiID
        self.foundAt = foundAt
        self.updatedAt = updatedAt
    }
}
