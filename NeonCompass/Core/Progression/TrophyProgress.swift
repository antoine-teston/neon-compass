import Foundation
import SwiftData

/// Suivi manuel des trophées (spec §5 : « checklists manuelles » — v1 n'a
/// aucune intégration PSN/Xbox ; l'utilisateur coche lui-même).
@Model
final class TrophyProgress {
    @Attribute(.unique) var trophyID: String

    init(trophyID: String) {
        self.trophyID = trophyID
    }
}
