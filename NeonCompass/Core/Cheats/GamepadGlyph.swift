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

/// Un code en TEXTE NU, pour là où l'on ne peut pas dessiner.
///
/// L'écran verrouillé, en l'occurrence : l'extension de widget ne compile pas les
/// vues de l'app, et à onze points un pictogramme de croix directionnelle devient
/// une tache. Les noms de boutons, eux, se lisent.
///
/// Ce n'est donc pas un doublon de `CheatCodeView` mais son pendant pour un autre
/// support — d'où la source unique ci-dessous : les deux tirent leurs boutons de
/// la même énumération, et un bouton ajouté ne peut pas manquer ici sans que le
/// compilateur le dise.
enum CheatCodePlainText {
    static func render(_ code: CheatCode) -> String {
        switch code {
        case .buttons(let buttons):
            buttons.map(label).joined(separator: " ")
        case .keyword(let word):
            word
        case .phone(let number, _):
            number
        }
    }

    static func label(_ button: GamepadButton) -> String {
        switch button {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        // Les formes PlayStation en caractères, faute de pouvoir les dessiner.
        case .cross: "✕"
        case .circle: "○"
        case .square: "□"
        case .triangle: "△"
        case .l1: "L1"
        case .l2: "L2"
        case .r1: "R1"
        case .r2: "R2"
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .lb: "LB"
        case .lt: "LT"
        case .rb: "RB"
        case .rt: "RT"
        }
    }
}
