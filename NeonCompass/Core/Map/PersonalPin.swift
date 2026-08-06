import Foundation
import SwiftData

/// Une entrée du carnet de chasse — marqueur strictement local, distinct de la
/// contribution communautaire (spec §5), qui requiert un compte.
///
/// **Chaque champ ajouté porte une valeur par défaut**, et c'est ce qui laisse
/// SwiftData faire sa migration légère seul : le conteneur de `NeonCompassApp`
/// n'a pas de `VersionedSchema` et n'a pas à en gagner un pour ce chantier.
///
/// `game` répare une fuite : sans lui, une épingle posée sur la carte de
/// référence s'affichait AUSSI sur Leonida, aux mêmes coordonnées normalisées —
/// donc à un endroit qui ne veut rien dire. Les épingles déjà en base
/// atterrissent sur la carte de référence, celle sur laquelle l'app s'ouvre.
///
/// `updatedAt` et `deletedAt` ne servent qu'au chantier 2 (synchro Pro) et sont
/// posés dès maintenant pour que la synchro soit un branchement et non une
/// migration. Le chantier 1 ÉCRIT `updatedAt` mais ne lit jamais `deletedAt` :
/// la suppression y reste physique.
@Model
final class PersonalPin: Identifiable {
    var id: UUID
    var x: Double
    var y: Double
    var game: String = Game.reference.rawValue
    /// Peut être vide, et ce n'est pas un oubli : l'épingle existe AVANT d'avoir
    /// un nom, puisqu'on la pose d'un geste et qu'on la nomme dans sa fiche. Le
    /// carnet affiche « Sans nom », jamais une ligne vide.
    var title: String
    var note: String = ""
    var icon: String = PersonalPinIcon.marker.rawValue
    var isDone: Bool = false
    var createdAt: Date
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        x: Double,
        y: Double,
        game: Game = .reference,
        title: String,
        note: String = "",
        icon: PersonalPinIcon = .marker,
        isDone: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.game = game.rawValue
        self.title = title
        self.note = note
        self.icon = icon.rawValue
        self.isDone = isDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = nil
    }

    var iconValue: PersonalPinIcon { PersonalPinIcon.from(rawValue: icon) }
    var gameValue: Game { Game(rawValue: game) ?? .reference }
    var position: NormalizedPoint { NormalizedPoint(x: x, y: y) }
}
