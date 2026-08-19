import Testing
import Foundation
@testable import NeonCompass

/// Une tuile manquante ne se signale nulle part : la couche laisse un carré de
/// socle agrandi, ce qui ressemble à du flou et non à une panne. Ce test est le
/// seul endroit où cela se voit, et il doit nommer la tuile ET la commande à
/// relancer — sinon il ne sert qu'à faire échouer la CI.
struct MapTileResourcesTests {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("NeonCompass/Resources")

    private static let paved = ["island-vi", "island-vi-classic"]

    private static func manifest(_ name: String) throws -> MapTileManifest {
        let url = resources.appendingPathComponent("MapTiles/\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MapTileManifest.self, from: data)
    }

    @Test func everyPavedMapShipsItsManifest() throws {
        for name in Self.paved {
            let m = try Self.manifest(name)
            #expect(m.tile == 512, "\(name) : tuile de \(m.tile) px, attendu 512")
            #expect(m.base == 4096, "\(name) : socle de \(m.base) px, attendu 4096")
            #expect(m.levels.map(\.side) == [9216, 18432], "\(name) : niveaux \(m.levels.map(\.side))")
            #expect(m.levels.map(\.count) == [18, 36], "\(name) : tuiles par côté \(m.levels.map(\.count))")
        }
    }

    /// Aucun trou hors tuiles uniformes déclarées, et réciproquement : une
    /// couleur déclarée pour une tuile qui existe ferait peindre un aplat
    /// par-dessus du contenu.
    @Test func everyTileIsEitherShippedOrDeclaredUniform() throws {
        for name in Self.paved {
            let m = try Self.manifest(name)
            for level in m.levels {
                let dir = Self.resources.appendingPathComponent("MapTiles/\(name)/\(level.side)")
                for y in 0..<level.count {
                    for x in 0..<level.count {
                        let key = "\(x)_\(y)"
                        let file = dir.appendingPathComponent("\(key).png")
                        let onDisk = FileManager.default.fileExists(atPath: file.path)
                        let declared = level.uniform[key] != nil
                        if onDisk == declared {
                            // `Issue.record` a deux surcharges (`Comment?` et `some Error`) qui se
                            // désambiguïsent sur le type SYNTAXIQUE de l'argument : un littéral
                            // interpolé passe, un ternaire ou une concaténation de littéraux se
                            // résout d'abord en `String` concret et casse l'inférence — d'où
                            // l'if/else plutôt qu'un ternaire ici, comme dans MapArtResourcesTests.
                            let label = "\(name)/\(level.side)/\(key).png"
                            if onDisk {
                                Issue.record("\(label) existe ET est déclarée uniforme")
                            } else {
                                Issue.record("\(label) absente et non déclarée uniforme — relancer node tools/basemap/gtavi-tiles.mjs")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func everyUniformColorIsSixHexDigits() throws {
        for name in Self.paved {
            let m = try Self.manifest(name)
            for level in m.levels {
                for (key, hex) in level.uniform {
                    #expect(
                        hex.count == 6 && hex.allSatisfy(\.isHexDigit),
                        "\(name)/\(level.side)/\(key) : couleur « \(hex) » illisible"
                    )
                }
            }
        }
    }

    /// Les deux habillages sortent du même cadrage : à niveau égal ils ont le
    /// même nombre de tuiles par côté. Sinon les épingles se décaleraient en
    /// basculant, ce que rien d'autre ne signalerait.
    @Test func bothStylesSharePyramidGeometry() throws {
        let neon = try Self.manifest("island-vi")
        let classic = try Self.manifest("island-vi-classic")
        #expect(neon.levels.map(\.side) == classic.levels.map(\.side))
        #expect(neon.levels.map(\.count) == classic.levels.map(\.count))
    }
}
