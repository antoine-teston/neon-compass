import SwiftUI

/// Habillage des pins par catégorie, décliné selon le fond de carte.
///
/// Deux jeux de couleurs, pas un seul teinté : les fonds sont trop différents
/// pour qu'un même pin fonctionne. Sur la carte restylée (fond nuit, terres
/// violettes) il faut des teintes claires et lumineuses ; sur la carte
/// d'origine (vert, sable, blanc, bleu clair) les mêmes couleurs deviennent
/// illisibles — on passe donc à des versions sombres et saturées, cerclées de
/// blanc plutôt que nimbées de néon.
///
/// Chaque catégorie porte AUSSI un symbole distinct. La couleur seule ne
/// suffit pas : six teintes ne sont pas distinguables pour une partie des
/// utilisateurs, et six halos concurrents contrediraient la sobriété visée par
/// le CLAUDE.md (« glow on at most three accents per screen »). Le symbole
/// porte l'information, la couleur la renforce.
enum POIPinPalette {
    static func color(for category: POICategory, style: MapStyle) -> Color {
        rgba(for: category, style: style).map(Color.init) ?? .white
    }

    /// Exposé pour que les tests vérifient les valeurs sans passer par `Color`,
    /// qui n'est pas introspectable.
    static func rgba(for category: POICategory, style: MapStyle) -> NCColor.RGBA? {
        NCColor.RGBA(hex: hex(for: category, style: style))
    }

    private static func hex(for category: POICategory, style: MapStyle) -> String {
        switch style {
        case .neon:
            switch category {
            // La catégorie la plus nombreuse (commodités) est aussi la plus
            // discrète : un bleu glacier neutre, pour ne pas manger les
            // accents de marque.
            case .landmark: "#9FD8FF"
            case .collectible: "#FF3388"  // NCColor.sunsetMagenta
            case .activity: "#26F2F2"     // NCColor.neonCyan
            // sunsetViolet éclairci : le violet de marque se noierait dans les
            // terres, elles-mêmes violettes.
            case .safehouse: "#C08BFF"
            case .vehicle: "#FF8C40"      // NCColor.sunsetOrange
            case .event: "#C6FF4D"
            }
        case .classic:
            switch category {
            case .landmark: "#12496E"
            case .collectible: "#A5116A"
            case .activity: "#0B6E7F"
            case .safehouse: "#5B21B6"
            case .vehicle: "#9A4B06"
            case .event: "#3F6212"
            }
        }
    }

    static func symbol(for category: POICategory) -> String {
        switch category {
        case .landmark: "building.columns.fill"
        case .collectible: "diamond.fill"
        case .activity: "flag.fill"
        case .safehouse: "house.fill"
        case .vehicle: "car.fill"
        case .event: "calendar"
        }
    }

    /// Contour du pin, qui le détache du fond quelle que soit la teinte
    /// dessous. Sombre sur la carte restylée, blanc sur la carte d'origine.
    static func outline(for style: MapStyle) -> Color {
        switch style {
        case .neon: Color(NCColor.RGBA(hex: "#050410")!)
        case .classic: .white
        }
    }

    /// Un halo néon n'a de sens que sur fond sombre — sur la carte d'origine
    /// il baverait en un flou laiteux au lieu de faire ressortir le pin.
    static func glowRadius(for style: MapStyle) -> CGFloat {
        switch style {
        case .neon: 4
        case .classic: 0
        }
    }
}
