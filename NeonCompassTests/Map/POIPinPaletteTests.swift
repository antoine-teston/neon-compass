import Testing
import SwiftUI
@testable import NeonCompass

struct POIPinPaletteTests {
    // Régression : une première version passait par une extension
    // `Color(hex:)` maison dont la résolution de surcharge produisait une
    // couleur transparente. Les pastilles se rendaient alors en cercles vides,
    // sans que rien n'échoue à la compilation — d'où ce test sur les valeurs
    // brutes plutôt que sur `Color`, qui n'est pas introspectable.
    @Test func everyCategoryResolvesToAnOpaqueColorInBothStyles() {
        for style in MapStyle.allCases {
            for category in POICategory.allCases {
                let rgba = POIPinPalette.rgba(for: category, style: style)
                #expect(rgba != nil, "\(category)/\(style) : hex invalide")
                #expect(rgba?.alpha == 1)
            }
        }
    }

    @Test func categoriesAreVisuallyDistinctWithinAStyle() {
        for style in MapStyle.allCases {
            let colors = POICategory.allCases.compactMap { POIPinPalette.rgba(for: $0, style: style) }
            #expect(colors.count == POICategory.allCases.count)
            #expect(Set(colors.map { "\($0.red)-\($0.green)-\($0.blue)" }).count == colors.count)
        }
    }

    /// L'exigence produit : la carte d'origine (fond clair) ne peut pas
    /// réutiliser les teintes pensées pour le fond nuit.
    @Test func classicStyleUsesDarkerColorsThanNeon() {
        for category in POICategory.allCases {
            guard let neon = POIPinPalette.rgba(for: category, style: .neon),
                  let classic = POIPinPalette.rgba(for: category, style: .classic) else {
                Issue.record("couleur manquante pour \(category)")
                continue
            }
            let neonLuma = neon.red + neon.green + neon.blue
            let classicLuma = classic.red + classic.green + classic.blue
            #expect(classicLuma < neonLuma, "\(category) : la variante classique doit être plus sombre")
        }
    }

    @Test func eachCategoryHasItsOwnSymbol() {
        let symbols = POICategory.allCases.map(POIPinPalette.symbol(for:))
        #expect(Set(symbols).count == symbols.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    /// Un halo néon sur fond clair baverait en flou laiteux au lieu de
    /// détacher le pin.
    @Test func glowIsNeonOnly() {
        #expect(POIPinPalette.glowRadius(for: .neon) > 0)
        #expect(POIPinPalette.glowRadius(for: .classic) == 0)
    }
}
