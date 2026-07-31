import Foundation

/// Quelle carte est affichée.
///
/// L'app est une compagne du jeu à venir, mais sa carte n'existe pas encore
/// publiquement : `leonida` n'a donc qu'un placeholder et un contenu éditorial
/// dont les POI attendent tous leur position. `reference` est la carte du
/// volet précédent, importée comme fixture (`tools/basemap/gtav-*.mjs`) — elle
/// donne une carte dense et réellement explorable en attendant.
///
/// Le type lui-même vit dans `Core/Game.swift` : la carte, le fil d'actu et les
/// codes nomment la même distinction, et ce fichier en portait une copie
/// jumelle de celle du fil. Ce nom reste parce qu'il se lit mieux ici — « la
/// carte du jeu » — et qu'il évite de toucher une dizaine de sites d'appel.
/// Aucune valeur n'est persistée (le choix de carte est un `@State`), donc rien
/// d'enregistré ne dépendait de ce renommage.
typealias MapGame = Game

extension Game {
    /// La carte de référence est la seule à exister en deux habillages : le
    /// placeholder est déjà dessiné aux couleurs de l'app, il n'a pas de
    /// variante « couleurs d'origine ».
    var supportsStyleToggle: Bool { self == .reference }
}

/// Variante d'habillage de la carte de référence.
///
/// `neon` est le défaut à CHAQUE ouverture, délibérément : c'est l'identité de
/// l'app, et le choix n'est donc pas persisté — rouvrir sur les couleurs
/// d'origine ferait perdre l'identité visuelle à quiconque a basculé une fois
/// pour lire un détail.
///
/// Les deux images sortent du même assemblage de tuiles, dans la même passe
/// (`tools/basemap/gtav-map.mjs`), donc strictement superposables : basculer ne
/// déplace aucun pin et n'invalide aucune coordonnée.
enum MapStyle: String, CaseIterable, Sendable {
    /// Restylée aux couleurs Neon Compass (`NCColor`).
    case neon
    /// Couleurs d'origine de la carte de référence — plus lisible pour
    /// distinguer relief, végétation et zones bâties.
    case classic
}

extension Game {
    /// Nom de la ressource image dans `MapArt/`.
    func resourceName(style: MapStyle) -> String {
        switch self {
        case .leonida: "island-vi"
        case .reference: style == .neon ? "island" : "island-classic"
        }
    }
}
