import Foundation
import SwiftData

/// Suivi manuel des trophées (spec §5 : « checklists manuelles » — v1 n'a
/// aucune intégration PSN/Xbox ; l'utilisateur coche lui-même).
@Model
final class TrophyProgress {
    @Attribute(.unique) var trophyID: String
    var updatedAt: Date = Date.now

    init(trophyID: String, updatedAt: Date = .now) {
        self.trophyID = trophyID
        self.updatedAt = updatedAt
    }
}
