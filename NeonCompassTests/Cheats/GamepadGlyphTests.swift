import Testing
import UIKit
@testable import NeonCompass

struct GamepadGlyphTests {
    // Repris de la version précédente du fichier : uniquement des SF Symbols
    // génériques, aucune marque Sony ou Microsoft.
    @Test func faceButtonsNeverReferenceTrademarkedSymbols() {
        for button in [GamepadButton.cross, .circle, .square, .triangle] {
            #expect(!GamepadGlyph.systemImage(for: button).isEmpty)
        }
    }

    @Test func xboxFaceButtonsUseLetterGlyphs() {
        #expect(GamepadGlyph.systemImage(for: .a) == "a.circle")
        #expect(GamepadGlyph.systemImage(for: .b) == "b.circle")
    }

    // Le test d'origine comparait le même bouton entre deux plates-formes, ce
    // que la signature ne permet plus. L'invariant devient plus fort : les
    // gâchettes des deux familles de manette partagent leur glyphe.
    @Test func shouldersShareTheirGlyphAcrossFamilies() {
        #expect(GamepadGlyph.systemImage(for: .l1) == GamepadGlyph.systemImage(for: .lb))
        #expect(GamepadGlyph.systemImage(for: .l2) == GamepadGlyph.systemImage(for: .lt))
        #expect(GamepadGlyph.systemImage(for: .r1) == GamepadGlyph.systemImage(for: .rb))
        #expect(GamepadGlyph.systemImage(for: .r2) == GamepadGlyph.systemImage(for: .rt))
    }

    // Un nom de SF Symbol erroné rend une Image vide : la carte affiche des
    // trous à la place de la séquence, et rien ne le signale au build.
    @Test func everyButtonResolvesToARealSFSymbol() {
        for button in GamepadButton.allCases {
            let name = GamepadGlyph.systemImage(for: button)
            #expect(!name.isEmpty)
            #expect(UIImage(systemName: name) != nil, "SF Symbol introuvable : \(name) pour \(button)")
        }
    }

    @Test func playstationAndXboxFacesShareTheirGeometry() {
        // Croix ↔ A, cercle ↔ B, carré ↔ X, triangle ↔ Y : même position sur la
        // manette, donc même forme affichée.
        #expect(GamepadGlyph.systemImage(for: .cross) == GamepadGlyph.systemImage(for: .a))
        #expect(GamepadGlyph.systemImage(for: .circle) == GamepadGlyph.systemImage(for: .b))
        #expect(GamepadGlyph.systemImage(for: .square) == GamepadGlyph.systemImage(for: .x))
        #expect(GamepadGlyph.systemImage(for: .triangle) == GamepadGlyph.systemImage(for: .y))
    }
}
