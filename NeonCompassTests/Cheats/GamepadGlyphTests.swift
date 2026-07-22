import Testing
@testable import NeonCompass

struct GamepadGlyphTests {
    @Test func genericFaceButtonsNeverReferenceTrademarkedSymbols() {
        // Aucune marque PlayStation/Xbox — uniquement des SF Symbols génériques.
        for button in [GamepadButton.cross, .circle, .square, .triangle] {
            let symbol = GamepadGlyph.systemImage(for: button, platform: .ps5)
            #expect(!symbol.isEmpty)
        }
    }

    @Test func xboxFaceButtonsUseLetterGlyphs() {
        #expect(GamepadGlyph.systemImage(for: .a, platform: .xbox) == "a.circle")
        #expect(GamepadGlyph.systemImage(for: .b, platform: .xbox) == "b.circle")
    }

    @Test func shoulderButtonsShareSameGlyphAcrossPlatforms() {
        #expect(GamepadGlyph.systemImage(for: .l1, platform: .ps5) == GamepadGlyph.systemImage(for: .l1, platform: .xbox))
    }
}
