import Testing
import Foundation
import CoreGraphics
@testable import NeonCompass

/// Le choix « quel niveau, quelles tuiles » décide à la fois de la netteté et
/// de l'empreinte mémoire. C'est une fonction pure, donc c'est ici qu'il se
/// vérifie — pas à l'œil sur un simulateur.
struct MapTileSetTests {
    /// Ce manifeste n'est PAS celui qui est livré — le livré est en 9 216 /
    /// 18 432. Les puissances de deux sont choisies pour que l'arithmétique
    /// reste lisible dans les attentes : 2 048 / 32 fait 64 pt pile, là où
    /// 2 048 / 36 ferait 56,888…, et un test dont on doit vérifier la valeur
    /// attendue à la calculatrice ne prouve plus rien. Ce qui doit coller au
    /// livré est vérifié par `MapTileResourcesTests`, sur le vrai fichier.
    private static let manifest = MapTileManifest(
        tile: 512,
        base: 4096,
        levels: [
            .init(side: 8192, count: 16, uniform: [:]),
            .init(side: 16384, count: 32, uniform: ["0_0": "0A081A"]),
        ]
    )

    // MARK: - Pixels affichables

    @Test func displayablePixelsMultipliesTheThreeFactors() {
        #expect(MapTileSet.displayablePixels(zoomScale: 3.3, contentSize: 2048, displayScale: 3) == 2048 * 3.3 * 3)
    }

    /// Deux gardes qui évitent une division par zéro plus loin : une échelle
    /// d'affichage n'est jamais sous 1, un zoom jamais négatif.
    @Test func displayablePixelsClampsDegenerateInputs() {
        #expect(MapTileSet.displayablePixels(zoomScale: 1, contentSize: 2048, displayScale: 0) == 2048)
        #expect(MapTileSet.displayablePixels(zoomScale: -1, contentSize: 2048, displayScale: 3) == 0)
    }

    // MARK: - Choix du niveau

    /// Sous le socle, aucune tuile : à 4 096 px affichables le socle en a déjà
    /// autant que l'écran peut montrer, et charger un niveau ferait payer la
    /// carte entière au repos — où toute la carte est visible.
    @Test func noTilesWhileTheBaseSuffices() {
        #expect(MapTileSet.level(for: 2642, manifest: Self.manifest) == nil)   // repos iPhone
        #expect(MapTileSet.level(for: 4096, manifest: Self.manifest) == nil)   // pile le socle
    }

    /// Au-dessus, le premier niveau assez défini — jamais le plus fin par défaut.
    @Test func theCoarsestSufficientLevelWins() {
        #expect(MapTileSet.level(for: 4097, manifest: Self.manifest) == 8192)
        #expect(MapTileSet.level(for: 8192, manifest: Self.manifest) == 8192)
        #expect(MapTileSet.level(for: 8193, manifest: Self.manifest) == 16384)
        #expect(MapTileSet.level(for: 16384, manifest: Self.manifest) == 16384)
    }

    /// Au-delà du plus fin on agrandit, mais on ne rend pas nil : rendre nil
    /// ferait retomber sur le socle au zoom maximal, soit l'inverse du but.
    @Test func beyondTheFinestLevelWeUpscaleRatherThanFallBack() {
        #expect(MapTileSet.level(for: 30000, manifest: Self.manifest) == 16384)
    }

    // MARK: - Fenêtre de tuiles

    /// Une tuile de 512 px au niveau 16 384 couvre 64 pt de l'espace de
    /// contenu de 2 048 pt. Un rectangle de 100 pt en coin en touche donc deux
    /// par axe, plus une marge d'une tuile.
    @Test func theWindowCoversTheVisibleRectPlusOneTileOfMargin() {
        let keys = MapTileSet.tiles(
            level: 16384,
            visibleContentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            contentSize: 2048, manifest: Self.manifest
        )
        #expect(Set(keys.map(\.x)) == [0, 1, 2])
        #expect(Set(keys.map(\.y)) == [0, 1, 2])
        #expect(keys.count == 9)
    }

    /// Les bords ne débordent jamais de la grille — une clé hors grille
    /// désignerait un fichier absent, indiscernable d'une tuile manquante.
    @Test func theWindowIsClampedToTheGrid() {
        let keys = MapTileSet.tiles(
            level: 8192,
            visibleContentRect: CGRect(x: 1900, y: 1900, width: 300, height: 300),
            contentSize: 2048, manifest: Self.manifest
        )
        #expect(keys.allSatisfy { (0..<16).contains($0.x) && (0..<16).contains($0.y) })
        #expect(keys.contains(MapTileKey(level: 8192, x: 15, y: 15)))
    }

    /// Un rectangle hors carte ne rend rien plutôt qu'une clé négative.
    @Test func anOffMapRectYieldsNothing() {
        let keys = MapTileSet.tiles(
            level: 8192,
            visibleContentRect: CGRect(x: -5000, y: -5000, width: 100, height: 100),
            contentSize: 2048, manifest: Self.manifest
        )
        #expect(keys.isEmpty)
    }

    /// Le repos demande TOUTES les tuiles du niveau : c'est justement pourquoi
    /// `level(for:)` rend nil sous le socle, et ce test fige la raison.
    @Test func theWholeMapAtRestWouldCostTheEntireLevel() {
        let keys = MapTileSet.tiles(
            level: 8192,
            visibleContentRect: CGRect(x: 0, y: 0, width: 2048, height: 2048),
            contentSize: 2048, manifest: Self.manifest
        )
        #expect(keys.count == 256)
    }

    /// `margin: 0` sur un rectangle nul pile sur une frontière de tuile
    /// inverse x0/x1 (et y0/y1) : à `step` 64, `minX = maxX = 128` donne
    /// `x0 = 2` et `x1 = 1`. Inatteignable avec la marge par défaut de 1 —
    /// mais les tâches 6/7 seront les premières à appeler `tiles` pour de
    /// vrai avec une marge de leur choix.
    @Test func aZeroMarginRectOnATileBoundaryYieldsNothingRatherThanCrashing() {
        let keys = MapTileSet.tiles(
            level: 16384,
            visibleContentRect: CGRect(x: 128, y: 128, width: 0, height: 0),
            contentSize: 2048, manifest: Self.manifest, margin: 0
        )
        #expect(keys.isEmpty)
    }

    // MARK: - Placement

    @Test func aTileFrameTilesTheContentSpaceExactly() {
        let f0 = MapTileSet.frame(for: MapTileKey(level: 16384, x: 0, y: 0), contentSize: 2048, manifest: Self.manifest)
        #expect(f0 == CGRect(x: 0, y: 0, width: 64, height: 64))
        let last = MapTileSet.frame(for: MapTileKey(level: 16384, x: 31, y: 31), contentSize: 2048, manifest: Self.manifest)
        #expect(abs(last.maxX - 2048) < 0.001)
        #expect(abs(last.maxY - 2048) < 0.001)
    }
}
