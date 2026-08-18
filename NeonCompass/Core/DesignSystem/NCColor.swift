import SwiftUI

enum NCColor {
    /// La forme composante, et non seulement la `Color` : Core Graphics et
    /// Core Animation ne savent pas lire une `Color` SwiftUI, et le fondu des
    /// bords de la carte doit peindre exactement cette teinte-là. Une seule
    /// écriture de l'hexadécimal, dont les deux formes descendent.
    static let nightSkyRGBA = RGBA(hex: "#0A081A")!
    static let nightSky = Color(nightSkyRGBA)

    /// Les trois arrêts de la rampe, dans l'ordre. Source unique : les trois
    /// couleurs nommées, le dégradé et `ramp(_:through:)` en sortent tous, donc
    /// une retouche de charte se fait ici et nulle part ailleurs.
    static let sunsetStops = [
        RGBA(hex: "#FF3388")!,
        RGBA(hex: "#8C33F2")!,
        RGBA(hex: "#FF8C40")!,
    ]

    /// La même famille, PRIVÉE DE SON VIOLET.
    ///
    /// Sert le dernier jour du compte à rebours. Le violet est la seule note
    /// froide de la rampe : la retirer fait passer toute la ligne au chaud —
    /// magenta, saumon, orange — sans quitter la charte ni renoncer au dégradé.
    ///
    /// C'est un signal plus discret qu'un aplat, et c'est assumé : le signal
    /// FORT du dernier jour reste la disparition de la colonne des jours.
    static let urgentStops = [sunsetStops[0], sunsetStops[2]]

    static let sunsetMagenta = Color(sunsetStops[0])
    static let sunsetViolet = Color(sunsetStops[1])
    static let sunsetOrange = Color(sunsetStops[2])
    /// L'accent principal — et il se rationne.
    ///
    /// Il a longtemps voulu dire « important », ce qui revenait à ne rien dire :
    /// tout est important, donc tout devenait cyan. Compté le 8 août 2026, il
    /// pesait 60 des 94 accents de l'app, quand le magenta en portait 18,
    /// l'orange 15 et le violet **1** — le dégradé `sunset`, cœur synthwave de
    /// la palette, ne servait presque nulle part. Un fil de six actus affichait
    /// sept accents cyan, là où la contrainte de design en plafonne trois par
    /// écran.
    ///
    /// **La règle : dans un élément qui se répète — une carte d'une liste, une
    /// ligne d'un tableau — l'accent va sur UN seul élément, le plus
    /// informatif.** Le libellé qui double une icône passe en blanc atténué ;
    /// l'icône garde la teinte. Là où c'est la valeur qui porte l'information et
    /// l'icône qui décore, c'est l'inverse.
    ///
    /// Ce qui garde le cyan sans discuter : l'app qui parle d'elle-même
    /// (mot-marque, onglet actif), la progression, et l'unique chose qu'un écran
    /// veut faire remarquer.
    static let neonCyan = Color(RGBA(hex: "#26F2F2")!)

    static let sunset = LinearGradient(
        colors: [sunsetMagenta, sunsetViolet, sunsetOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Un point d'une rampe, de 0 (premier arrêt) à 1 (dernier). Hors bornes, on
    /// se rabat sur l'extrémité la plus proche.
    ///
    /// Sert à teinter une SUITE d'éléments distincts — les colonnes du compte à
    /// rebours — comme si un seul dégradé les traversait. Un `LinearGradient`
    /// posé sur chacun repartirait de zéro à l'intérieur de chaque élément :
    /// autant de petits dégradés au lieu d'un grand.
    ///
    /// `stops` doit en compter au moins deux. Les deux seuls appelants passent
    /// des constantes de ce fichier, donc ça ne se vérifie pas à l'exécution.
    static func ramp(_ position: Double, through stops: [RGBA]) -> Color {
        Color(rampRGBA(position, through: stops))
    }

    /// Le calcul, séparé de son emballage `Color` pour être testable — une
    /// `Color` SwiftUI ne rend pas ses composantes.
    static func rampRGBA(_ position: Double, through stops: [RGBA]) -> RGBA {
        let clamped = min(max(position, 0), 1)
        let scaled = clamped * Double(stops.count - 1)
        // Le `min` retient le DERNIER segment quand `position` vaut 1 : sans
        // lui, l'index déborderait d'une case au sommet de la rampe.
        let segment = min(Int(scaled), stops.count - 2)
        let ratio = scaled - Double(segment)
        let from = stops[segment]
        let to = stops[segment + 1]
        return RGBA(
            red: from.red + (to.red - from.red) * ratio,
            green: from.green + (to.green - from.green) * ratio,
            blue: from.blue + (to.blue - from.blue) * ratio,
            alpha: 1
        )
    }

    struct RGBA: Equatable, Sendable {
        let red: Double, green: Double, blue: Double, alpha: Double

        init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        init?(hex: String) {
            var s = hex.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1.0
        }
    }
}

extension Color {
    init(_ rgba: NCColor.RGBA) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
