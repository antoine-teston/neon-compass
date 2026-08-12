import Testing
import Foundation
@testable import NeonCompass

/// Garde les deux choses que le moteur de carte ne sait PAS signaler.
///
/// Une ressource manquante : `MapArtLoader.image` rend nil et le contenu se
/// dessine sans image — carte noire sous les épingles, aucune erreur, aucun
/// avertissement de compilation. Et deux habillages aux dimensions différentes :
/// les positions d'épingles sont normalisées sur le côté du contenu, donc un
/// recadrage divergent les décalerait toutes en basculant, sans rien casser non
/// plus.
///
/// Lit le dépôt et non `Bundle.main` : NeonCompassTests n'est pas hébergé dans
/// le process de l'app (TEST_HOST non configuré), donc `Bundle.main` désigne le
/// runner de test. Même contournement que `POITests.seedFileIsValidJSON`.
struct MapArtResourcesTests {
    private static let mapArt = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("NeonCompass/Resources/MapArt")

    /// Côté d'un PNG, lu dans l'en-tête IHDR — 8 octets de signature, puis
    /// longueur et type du chunk, puis largeur et hauteur en gros-boutien.
    private static func pngSize(_ url: URL) throws -> (width: Int, height: Int) {
        let header = try FileHandle(forReadingFrom: url).read(upToCount: 24) ?? Data()
        try #require(header.count == 24, "\(url.lastPathComponent) : en-tête PNG tronqué")
        func int32(at offset: Int) -> Int {
            header[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }
        }
        return (int32(at: 16), int32(at: 20))
    }

    @Test func everyGameAndStyleHasItsImage() throws {
        for game in Game.allCases {
            for style in MapStyle.allCases {
                let name = game.resourceName(style: style)
                let url = Self.mapArt.appendingPathComponent("\(name).png")
                #expect(
                    FileManager.default.fileExists(atPath: url.path),
                    "\(name).png absent de Resources/MapArt — la carte \(game.shortLabel) serait noire en \(style.rawValue)"
                )
            }
        }
    }

    /// Ce qui rend la bascule d'habillage réelle plutôt qu'un bouton mort : les
    /// deux styles d'une même carte doivent désigner deux fichiers distincts.
    @Test func stylesOfTheSameMapNameDistinctImages() {
        for game in Game.allCases {
            #expect(
                game.resourceName(style: .neon) != game.resourceName(style: .classic),
                "carte \(game.shortLabel) : les deux habillages désignent la même image"
            )
        }
    }

    /// La superposabilité que promet la documentation de `MapStyle`, vérifiée
    /// plutôt que supposée : elle vient du générateur, qui recadre les deux
    /// habillages dans la même passe.
    @Test func bothStylesShareTheSameSquareFrame() throws {
        for game in Game.allCases {
            let sizes = try MapStyle.allCases.map {
                try Self.pngSize(Self.mapArt.appendingPathComponent("\(game.resourceName(style: $0)).png"))
            }
            #expect(sizes[0] == sizes[1], "carte \(game.shortLabel) : habillages de dimensions différentes \(sizes)")
            #expect(sizes[0].width == sizes[0].height, "carte \(game.shortLabel) : carte non carrée \(sizes[0])")
        }
    }
}
