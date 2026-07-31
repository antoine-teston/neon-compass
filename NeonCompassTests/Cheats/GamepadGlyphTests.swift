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
        #expect(GamepadGlyph.systemImage(for: .x) == "x.circle")
        #expect(GamepadGlyph.systemImage(for: .y) == "y.circle")
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

    // L'inverse de ce que ce fichier affirmait.
    //
    // Une version antérieure faisait partager leurs glyphes aux boutons de même
    // position — croix rendue comme A, carré comme X — et un test verrouillait
    // cette égalité. Sur simulateur, le mode PlayStation affichait donc Ⓨ Ⓧ Ⓑ :
    // des lettres absentes de cette manette. Chaque famille garde ses formes.
    @Test func eachControllerFamilyKeepsItsOwnFaceGlyphs() {
        #expect(GamepadGlyph.systemImage(for: .cross) != GamepadGlyph.systemImage(for: .a))
        #expect(GamepadGlyph.systemImage(for: .circle) != GamepadGlyph.systemImage(for: .b))
        #expect(GamepadGlyph.systemImage(for: .square) != GamepadGlyph.systemImage(for: .x))
        #expect(GamepadGlyph.systemImage(for: .triangle) != GamepadGlyph.systemImage(for: .y))
    }

    // Même raison pour les gâchettes : un joueur Xbox qui cherche LB ne doit pas
    // lire L1.
    @Test func eachControllerFamilyKeepsItsOwnShoulderGlyphs() {
        #expect(GamepadGlyph.systemImage(for: .l1) != GamepadGlyph.systemImage(for: .lb))
        #expect(GamepadGlyph.systemImage(for: .l2) != GamepadGlyph.systemImage(for: .lt))
        #expect(GamepadGlyph.systemImage(for: .r1) != GamepadGlyph.systemImage(for: .rb))
        #expect(GamepadGlyph.systemImage(for: .r2) != GamepadGlyph.systemImage(for: .rt))
    }

    // Les formes PlayStation sont de la géométrie nue, pas un jeu de glyphes de
    // marque : c'est ce qui les rend utilisables sans reproduire quoi que ce soit.
    @Test func playstationFacesUseBareGeometry() {
        #expect(GamepadGlyph.systemImage(for: .triangle) == "triangle.circle")
        #expect(GamepadGlyph.systemImage(for: .square) == "square.circle")
        #expect(GamepadGlyph.systemImage(for: .circle) == "circle.circle")
        #expect(GamepadGlyph.systemImage(for: .cross) == "xmark.circle")
    }

    // Aucun glyphe partagé entre deux boutons distincts : deux boutons rendus
    // pareil rendent le code ambigu, quelle que soit la raison esthétique.
    @Test func noTwoButtonsRenderIdentically() {
        var seen: [String: GamepadButton] = [:]
        for button in GamepadButton.allCases {
            let name = GamepadGlyph.systemImage(for: button)
            if let clash = seen[name] {
                Issue.record("\(button) et \(clash) partagent le glyphe \(name)")
            }
            seen[name] = button
        }
    }
}
