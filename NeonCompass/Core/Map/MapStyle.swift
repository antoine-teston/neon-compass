import Foundation

/// Quelle carte est affichée.
///
/// L'app est une compagne du jeu à venir, mais sa carte n'existe pas encore
/// publiquement : `leonida` n'a donc qu'un placeholder et un contenu éditorial
/// dont les POI attendent tous leur position. `reference` est la carte du
/// volet précédent, importée comme fixture (`tools/basemap/gtav-*.mjs`) — elle
/// donne une carte dense et réellement explorable en attendant.
///
/// Les libellés exposés à l'UI sont des chiffres romains nus, jamais la marque
/// elle-même : CLAUDE.md interdit les marques déposées dans l'app.
/// Les valeurs brutes sont celles du contenu (`content/schema/collection.schema.json`),
/// pas les noms de cas : `reference` se lit bien dans le code — « la carte de
/// référence » — mais ne veut rien dire dans le dépôt de contenu, où `gtav`
/// est explicite. Une seule correspondance, ici, plutôt que deux vocabulaires
/// qui dérivent. Aucune valeur n'est persistée (le choix de carte est un
/// `@State`), donc les renommer ne casse aucune préférence enregistrée.
enum MapGame: String, Codable, CaseIterable, Identifiable, Sendable {
    case leonida
    case reference = "gtav"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .leonida: "VI"
        case .reference: "V"
        }
    }

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

extension MapGame {
    /// Nom de la ressource image dans `MapArt/`.
    func resourceName(style: MapStyle) -> String {
        switch self {
        case .leonida: "island-vi"
        case .reference: style == .neon ? "island" : "island-classic"
        }
    }
}
