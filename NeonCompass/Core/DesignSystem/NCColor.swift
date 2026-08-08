import SwiftUI

enum NCColor {
    static let nightSky = Color(RGBA(hex: "#0A081A")!)

    /// Les trois arrêts de la rampe, dans l'ordre. Source unique : les trois
    /// couleurs nommées, le dégradé et `sunsetRamp(_:)` en sortent tous, donc
    /// une retouche de charte se fait ici et nulle part ailleurs.
    static let sunsetStops = [
        RGBA(hex: "#FF3388")!,
        RGBA(hex: "#8C33F2")!,
        RGBA(hex: "#FF8C40")!,
    ]

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

    /// Un point de la rampe `sunset`, de 0 (magenta) à 1 (orange), violet au
    /// milieu. Hors bornes, on se rabat sur l'extrémité la plus proche.
    ///
    /// Sert à teinter une SUITE d'éléments distincts — les quatre colonnes du
    /// compte à rebours — comme si un seul dégradé les traversait. Un
    /// `LinearGradient` posé sur chacun repartirait de zéro à l'intérieur de
    /// chaque élément : quatre petits dégradés au lieu d'un grand.
    static func sunsetRamp(_ position: Double) -> Color {
        Color(sunsetRampRGBA(position))
    }

    /// Le calcul, séparé de son emballage `Color` pour être testable — une
    /// `Color` SwiftUI ne rend pas ses composantes.
    static func sunsetRampRGBA(_ position: Double) -> RGBA {
        let clamped = min(max(position, 0), 1)
        let scaled = clamped * Double(sunsetStops.count - 1)
        // Le `min` retient le DERNIER segment quand `position` vaut 1 : sans
        // lui, l'index déborderait d'une case au sommet de la rampe.
        let segment = min(Int(scaled), sunsetStops.count - 2)
        let ratio = scaled - Double(segment)
        let from = sunsetStops[segment]
        let to = sunsetStops[segment + 1]
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
