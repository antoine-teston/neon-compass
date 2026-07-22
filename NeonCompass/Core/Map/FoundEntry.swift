import Foundation
import SwiftData

/// Source de vérité unique carte↔checklists (spec §5, réutilisée au plan 4).
@Model
final class FoundEntry {
    @Attribute(.unique) var poiID: String
    var foundAt: Date

    init(poiID: String, foundAt: Date = .now) {
        self.poiID = poiID
        self.foundAt = foundAt
    }
}
