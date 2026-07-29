import Foundation

/// Uniquement des SF Symbols génériques (formes géométriques, lettres) —
/// jamais un logo ou glyphe propriétaire Sony/Microsoft.
///
/// Plus de paramètre `platform:` : le jeton porte déjà sa famille de manette.
/// `cross` et `a` sont deux cas distincts qui se rendent pareil, ce qui est
/// exactement l'information voulue — même position sur la manette, même forme
/// à l'écran — sans qu'un appelant ait à savoir quelle manette il affiche.
enum GamepadGlyph {
    static func systemImage(for button: GamepadButton) -> String {
        switch button {
        case .up: "dpad.up.filled"
        case .down: "dpad.down.filled"
        case .left: "dpad.left.filled"
        case .right: "dpad.right.filled"
        // Les gâchettes des deux familles partagent leur glyphe : SF Symbols a
        // bien des variantes `lb`/`rt`, mais une seule famille de formes évite
        // qu'une manette paraisse mieux traitée que l'autre, et le libellé du
        // mode de saisie lève déjà l'ambiguïté.
        case .l1, .lb: "l1.button.roundedbottom.horizontal"
        case .l2, .lt: "l2.button.roundedtop.horizontal"
        case .r1, .rb: "r1.button.roundedbottom.horizontal"
        case .r2, .rt: "r2.button.roundedtop.horizontal"
        case .cross, .a: "a.circle"
        case .circle, .b: "b.circle"
        case .square, .x: "x.circle"
        case .triangle, .y: "y.circle"
        }
    }
}
