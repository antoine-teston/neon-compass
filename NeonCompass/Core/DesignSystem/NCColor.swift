import SwiftUI

enum NCColor {
    static let nightSky = Color(RGBA(hex: "#0A081A")!)
    static let sunsetMagenta = Color(RGBA(hex: "#FF3388")!)
    static let sunsetViolet = Color(RGBA(hex: "#8C33F2")!)
    static let sunsetOrange = Color(RGBA(hex: "#FF8C40")!)
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

    struct RGBA: Equatable, Sendable {
        let red: Double, green: Double, blue: Double, alpha: Double

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
