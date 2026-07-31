import Foundation

/// Uniquement des SF Symbols génériques (formes géométriques, lettres) —
/// jamais un logo ou glyphe propriétaire Sony/Microsoft. Un triangle dans un
/// cercle est de la géométrie ; ce que la marque protège, c'est son jeu de
/// glyphes stylisé, qu'on ne reproduit pas.
///
/// Plus de paramètre `platform:` : le jeton porte déjà sa famille de manette.
///
/// Chaque famille garde ses propres formes, délibérément. Une première version
/// les faisait partager les mêmes glyphes — croix et A rendus pareil, L1 et LB
/// rendus pareil — au motif qu'aucune manette ne devait paraître mieux traitée
/// que l'autre. À l'écran, le mode PlayStation affichait Ⓨ Ⓧ Ⓑ : des lettres
/// qui n'existent pas sur cette manette. Un code qu'on ne peut pas lire ne se
/// saisit pas, et c'est la seule chose que cet écran ait à faire.
enum GamepadGlyph {
    static func systemImage(for button: GamepadButton) -> String {
        switch button {
        case .up: "dpad.up.filled"
        case .down: "dpad.down.filled"
        case .left: "dpad.left.filled"
        case .right: "dpad.right.filled"

        // PlayStation : les formes, pas les lettres.
        case .cross: "xmark.circle"
        case .circle: "circle.circle"
        case .square: "square.circle"
        case .triangle: "triangle.circle"
        case .l1: "l1.button.roundedbottom.horizontal"
        case .l2: "l2.button.roundedtop.horizontal"
        case .r1: "r1.button.roundedbottom.horizontal"
        case .r2: "r2.button.roundedtop.horizontal"

        // Xbox : les lettres, et ses propres gâchettes.
        case .a: "a.circle"
        case .b: "b.circle"
        case .x: "x.circle"
        case .y: "y.circle"
        case .lb: "lb.button.roundedbottom.horizontal"
        case .lt: "lt.button.roundedtop.horizontal"
        case .rb: "rb.button.roundedbottom.horizontal"
        case .rt: "rt.button.roundedtop.horizontal"
        }
    }
}
