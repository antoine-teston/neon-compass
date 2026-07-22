import Foundation

/// Uniquement des SF Symbols génériques (formes géométriques, lettres) —
/// jamais un logo ou glyphe propriétaire Sony/Microsoft.
enum GamepadGlyph {
    static func systemImage(for button: GamepadButton, platform: Platform) -> String {
        switch button {
        case .up: "dpad.up.filled"
        case .down: "dpad.down.filled"
        case .left: "dpad.left.filled"
        case .right: "dpad.right.filled"
        case .l1: "l1.button.roundedbottom.horizontal"
        case .l2: "l2.button.roundedtop.horizontal"
        case .r1: "r1.button.roundedbottom.horizontal"
        case .r2: "r2.button.roundedtop.horizontal"
        case .cross, .a: "a.circle"
        case .circle, .b: "b.circle"
        case .square, .x: "x.circle"
        case .triangle, .y: "y.circle"
        }
    }
}
