import Foundation

/// Quelle carte est affichée.
///
/// Les deux cartes sont maintenant de vraies cartes explorables : `leonida` est
/// la carte communautaire de Leonida assemblée puis restylée par
/// `tools/basemap/gtavi-map.mjs`, `reference` celle du volet précédent
/// (`tools/basemap/gtav-*.mjs`). Ce qui les distingue encore est la densité du
/// contenu éditorial, pas l'illustration : sur `leonida` les POI attendent
/// toujours leur position.
///
/// Le type lui-même vit dans `Core/Game.swift` : la carte, le fil d'actu et les
/// codes nomment la même distinction, et ce fichier en portait une copie
/// jumelle de celle du fil. Ce nom reste parce qu'il se lit mieux ici — « la
/// carte du jeu » — et qu'il évite de toucher une dizaine de sites d'appel.
/// Aucune valeur n'est persistée (le choix de carte est un `@State`), donc rien
/// d'enregistré ne dépendait de ce renommage.
typealias MapGame = Game

/// Variante d'habillage de la carte affichée.
///
/// `neon` est le défaut à CHAQUE ouverture, délibérément : c'est l'identité de
/// l'app, et le choix n'est donc pas persisté — rouvrir sur les couleurs
/// d'origine ferait perdre l'identité visuelle à quiconque a basculé une fois
/// pour lire un détail.
///
/// Les deux habillages d'une même carte sortent du même assemblage de tuiles et
/// du même recadrage, dans la même passe (`--restyle --classic`), donc
/// strictement superposables : basculer ne déplace aucun pin et n'invalide
/// aucune coordonnée. C'est cette garantie qui rend la bascule sûre, et elle
/// vient du générateur — pas du code de l'app, qui ne peut que la supposer.
enum MapStyle: String, CaseIterable, Sendable {
    /// Restylée aux couleurs Neon Compass (`NCColor`).
    case neon
    /// Couleurs d'origine de la carte source — plus lisible pour distinguer
    /// relief, végétation et zones bâties.
    case classic
}

extension Game {
    /// Nom de la ressource image dans `MapArt/`.
    ///
    /// Le suffixe est le même pour les deux cartes parce que le générateur le
    /// pose lui-même : `island[-vi][-classic].png`. Une correspondance cas par
    /// cas se serait désynchronisée du jour où une troisième carte arrive.
    func resourceName(style: MapStyle) -> String {
        let base = switch self {
        case .leonida: "island-vi"
        case .reference: "island"
        }
        return style == .neon ? base : "\(base)-classic"
    }

    /// Source du fond de carte d'origine, à créditer à l'écran sous l'habillage
    /// `classic`.
    ///
    /// Nomme le JEU DE TUILES et son hôte, jamais un auteur : c'est tout ce que
    /// les URL de génération permettent d'affirmer, et l'auteur de ces deux
    /// cartes communautaires n'a pas été retrouvé (voir
    /// `tools/basemap/SOURCES.md`). Un crédit inventé serait pire qu'un crédit
    /// imprécis.
    ///
    /// Destiné à un `Text(verbatim:)` dans une fente nominative, jamais à
    /// l'intérieur d'une phrase que nous écrivons : `gtavmap` porte une marque
    /// Rockstar, et c'est la POSITION qui la rend admissible (cf. `CLAUDE.md`).
    /// Hors du catalogue de chaînes pour la même raison — un nom de produit est
    /// identique dans les cinq langues.
    var basemapCredit: String {
        switch self {
        case .leonida: "YANIS v14 · map.stateofleonida.net"
        case .reference: "gtavmap · s3-eu-west-1.amazonaws.com"
        }
    }
}
