import Testing
import Foundation
@testable import NeonCompass

/// Garde les trois choses que le moteur de carte ne sait PAS signaler.
///
/// Une ressource manquante : `MapArtLoader.cached` rend nil et le contenu se
/// dessine sans image — carte noire sous les épingles, aucune erreur, aucun
/// avertissement de compilation. Deux habillages aux dimensions différentes :
/// les positions d'épingles sont normalisées sur le côté du contenu, donc un
/// recadrage divergent les décalerait toutes en basculant, sans rien casser non
/// plus. Et un `-reduced.png` absent ou à la mauvaise définition : l'app se
/// rabat sur le natif, la carte reste juste, et le seul symptôme est le retour
/// des 256 Mio et de la latence que les deux étages venaient d'enlever.
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

    /// Troisième panne muette de la même famille : un fond de carte d'origine
    /// livré SANS crédit. Rien ne casse, rien ne se voit — et c'est exactement le
    /// risque que le crédit existe pour couvrir, puisque ces deux cartes sont
    /// l'œuvre de tiers (voir `tools/basemap/SOURCES.md`).
    @Test func everyMapCreditsItsOriginalSource() {
        for game in Game.allCases {
            let credit = game.basemapCredit
            #expect(
                !credit.trimmingCharacters(in: .whitespaces).isEmpty,
                "carte \(game.shortLabel) : habillage classic livré sans crédit de source"
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

    /// L'étage réduit est un FICHIER, et c'est là que sa livraison se vérifie.
    ///
    /// Deux exigences, pas une. Qu'il existe dès que le natif dépasse
    /// `overviewMaxPixels` : sinon `MapArtLoader` se rabat sur le natif et
    /// l'économie disparaît sans un mot. Et qu'il fasse EXACTEMENT la définition
    /// déclarée : un fichier plus grand paierait plus que prévu, un plus petit
    /// serait agrandi au-delà de ce que `MapArtDetailSelector` tolère — dans les
    /// deux cas le sélecteur raisonnerait sur une valeur fausse, puisqu'il
    /// compare les pixels affichables à cette constante et non au fichier.
    ///
    /// Le natif de 4 096 px n'a rien à réduire : c'est le cas de la carte de
    /// référence, et le repli du loader est alors le chemin normal.
    @Test func theReducedTierIsShippedAtItsDeclaredSize() throws {
        for game in Game.allCases {
            for style in MapStyle.allCases {
                let name = game.resourceName(style: style)
                let native = try Self.pngSize(Self.mapArt.appendingPathComponent("\(name).png"))
                let reduced = Self.mapArt.appendingPathComponent("\(name)\(MapArtDetail.reducedSuffix).png")
                guard native.width > MapArtDetail.overviewMaxPixels else {
                    #expect(
                        !FileManager.default.fileExists(atPath: reduced.path),
                        "\(name) fait \(native.width) px : un étage réduit n'y ajouterait que du poids"
                    )
                    continue
                }
                guard FileManager.default.fileExists(atPath: reduced.path) else {
                    let fix = "relancer tools/basemap/reduce-mapart.mjs"
                    Issue.record("\(reduced.lastPathComponent) absent — l'app décodera \(native.width) px au repos (\(fix))")
                    continue
                }
                let size = try Self.pngSize(reduced)
                #expect(
                    size == (MapArtDetail.overviewMaxPixels, MapArtDetail.overviewMaxPixels),
                    "\(reduced.lastPathComponent) fait \(size), attendu \(MapArtDetail.overviewMaxPixels) px de côté"
                )
            }
        }
    }
}
