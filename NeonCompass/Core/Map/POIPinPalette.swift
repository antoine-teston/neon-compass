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

    /// Cœur de l'épingle — délibérément NEUTRE, et non plus la couleur de
    /// catégorie.
    ///
    /// C'est le renversement dont découle tout le reste. Un disque rempli en
    /// couleur de catégorie est une gommette opaque, et il y en a plus de cent à
    /// l'écran au zoom de repos : le fond de carte, qui est le meilleur atout de
    /// l'app, disparaissait entièrement dessous. Or le néon est un tube fin — la
    /// lumière est sur le CONTOUR, jamais dans la masse. Le cœur laisse donc
    /// passer la trame viaire, et c'est l'anneau qui porte la couleur.
    ///
    /// L'objection que cette palette portait jusqu'ici — « un symbole teinté sur
    /// fond sombre se réduit à un point flou » — visait un pin SANS anneau. Elle
    /// ne tient plus : l'anneau donne un bord franc et lumineux, donc une
    /// silhouette, ce qu'un simple glyphe teinté n'avait pas.
    static func core(for style: MapStyle) -> Color {
        switch style {
        // Plus sombre que les terres (violettes) comme que l'eau (presque
        // noire) : le cœur creuse, quel que soit l'endroit de la carte.
        case .neon: Color(NCColor.RGBA(hex: "#07061A")!)
        // Le fond d'origine est clair (vert, sable, blanc) : c'est vers le blanc
        // qu'il faut s'écarter pour que l'anneau sombre et saturé ressorte.
        case .classic: .white
        }
    }

    /// Opacité du cœur. Le trouvé est plus TRANSPARENT, pas plus terne : c'est
    /// ce qui le rend plus léger que le non-trouvé sans le rendre boueux.
    static func coreOpacity(found: Bool) -> Double {
        found ? 0.45 : 0.82
    }

    /// Épaisseur de l'anneau. Le trouvé s'amincit — même geste que l'opacité, et
    /// pour la même raison : ce qui reste à faire doit accrocher l'œil, pas
    /// l'inverse.
    static func ringWidth(found: Bool) -> CGFloat {
        found ? 1.5 : 2
    }

    /// Le halo ne survit pas au marquage : un lieu trouvé cesse d'émettre. C'est
    /// aussi ce qui tient la consigne du CLAUDE.md (« glow on at most three
    /// accents per screen ») à mesure que la carte se complète.
    static func glowRadius(for style: MapStyle, found: Bool) -> CGFloat {
        found ? 0 : glowRadius(for: style)
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
