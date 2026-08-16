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

    /// Celui-ci reprend au contraire les côtés RÉELLEMENT livrés — 9 216 et
    /// 18 432 — parce que les valeurs attendues du plafond sont ici les
    /// valeurs réelles, 3,3 et 4,95, et qu'un test du plafond écrit sur des
    /// puissances de deux inventées ne dirait rien de l'app.
    private static let shippedShapedManifest = MapTileManifest(
        tile: 512,
        base: 4096,
        levels: [
            .init(side: 9216, count: 18, uniform: [:]),
            .init(side: 18432, count: 36, uniform: [:]),
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

    // MARK: - Plafond de zoom

    /// Les deux valeurs iPhone d'aujourd'hui, retrouvées par la formule. C'est
    /// la seule chose qui autorise à remplacer deux constantes par un calcul :
    /// s'il ne les redonnait pas, il changerait le comportement en douce.
    @Test func theCeilingReproducesTodaysIPhoneConstants() {
        let pyramided = MapTileSet.maximumZoomScale(
            contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 3
        )
        #expect(abs(pyramided - 3.3) < 0.0001)
        let bare = MapTileSet.maximumZoomScale(contentSize: 2048, manifest: nil, displayScale: 3)
        #expect(abs(bare - 2.5) < 0.0001)
    }

    /// Et ce qu'elles deviennent sur un appareil ×2 : la même finesse à
    /// l'écran demande un zoom une fois et demie plus grand. C'est tout
    /// l'objet de ce chantier — l'iPad s'arrêtait à 73 % de ce qu'il embarque.
    @Test func theCeilingRisesOnATwoTimesDevice() {
        let pyramided = MapTileSet.maximumZoomScale(
            contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 2
        )
        #expect(abs(pyramided - 4.95) < 0.0001)
        let bare = MapTileSet.maximumZoomScale(contentSize: 2048, manifest: nil, displayScale: 2)
        #expect(abs(bare - 3.75) < 0.0001)
    }

    /// La même finesse à l'écran, littéralement : à leurs plafonds respectifs,
    /// les deux appareils réclament le même nombre de pixels source par point
    /// d'écran. Aucune des deux fonctions testées ne connaît l'autre appareil,
    /// donc cette égalité n'est pas une tautologie — c'est la propriété que la
    /// formule est censée produire.
    @Test func bothDevicesEndOnTheSameSourcePixelDensity() {
        let onThree = MapTileSet.displayablePixels(
            zoomScale: MapTileSet.maximumZoomScale(contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 3),
            contentSize: 2048, displayScale: 3
        )
        let onTwo = MapTileSet.displayablePixels(
            zoomScale: MapTileSet.maximumZoomScale(contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 2),
            contentSize: 2048, displayScale: 2
        )
        #expect(abs(onThree - onTwo) < 1)
        #expect(abs(onThree - 18432 * 1.10) < 1)
    }

    /// Un manifeste sans niveau n'est pas une pyramide : il retombe sur le
    /// socle, et non sur une division par un côté nul.
    @Test func aLevellessManifestFallsBackToTheBareBase() {
        let empty = MapTileManifest(tile: 512, base: 4096, levels: [])
        let ceiling = MapTileSet.maximumZoomScale(contentSize: 2048, manifest: empty, displayScale: 3)
        #expect(abs(ceiling - 2.5) < 0.0001)
    }

    /// Deux entrées dégénérées, toutes deux atteignables : une vue pas encore
    /// posée a une échelle d'affichage de 0, et un contenu de côté nul rendrait
    /// un plafond infini qu'`UIScrollView` accepterait sans broncher.
    ///
    /// La spec en listait une troisième — « tolérance nulle » — qui n'a plus
    /// d'objet : la tolérance n'est pas un paramètre mais une constante du
    /// type, donc aucun appelant ne peut la mettre à zéro. Le cas structurel
    /// équivalent, un manifeste sans niveau, est couvert juste au-dessus.
    @Test func theCeilingSurvivesDegenerateInputs() {
        let noScale = MapTileSet.maximumZoomScale(
            contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 0
        )
        #expect(abs(noScale - 18432 * 1.10 / 2048) < 0.0001)
        let noContent = MapTileSet.maximumZoomScale(
            contentSize: 0, manifest: Self.shippedShapedManifest, displayScale: 3
        )
        #expect(noContent == 1)
    }
}
