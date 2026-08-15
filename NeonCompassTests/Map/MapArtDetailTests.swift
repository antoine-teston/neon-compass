import Testing
import CoreGraphics
@testable import NeonCompass

/// Le seul morceau vérifiable du chargement d'image : QUAND on paie l'étage
/// natif. Le décodage lui-même ne l'est pas ici — le bundle de test n'embarque
/// pas `MapArt/` (voir `MapArtResourcesTests`) — mais la décision, si.
///
/// Ce qu'il y a à garder n'est pas une valeur, c'est un encadrement : l'étage
/// réduit doit couvrir toute la plage où l'on CONSULTE la carte, et l'étage natif
/// doit être là quand on y POSE quelque chose. Ces deux bornes viennent du
/// produit, pas du code, et rien dans le code ne les rappellerait si un seuil
/// dérivait.
struct MapArtDetailTests {
    /// Le carré de contenu, en points — `MapManifest.size`.
    private static let contentSize: CGFloat = 2048
    /// Échelle de repos mesurée : la carte remplit l'écran sur les deux axes.
    private static let restingIPhone: CGFloat = 0.427
    private static let restingIPad: CGFloat = 0.67

    private func detail(zoom: CGFloat, displayScale: CGFloat, from start: MapArtDetail = .overview) -> MapArtDetail {
        var selector = MapArtDetailSelector()
        // L'état de départ ne s'écrit pas : on l'atteint. Un zoom au plafond fait
        // monter, ce qui est le seul chemin vers `.full`.
        if start == .full {
            selector.update(zoomScale: 2.5, contentSize: Self.contentSize, displayScale: displayScale)
        }
        return selector.update(zoomScale: zoom, contentSize: Self.contentSize, displayScale: displayScale)
    }

    /// Ce que la décision achète : au lancement, on ne paie pas les 256 Mo.
    @Test(arguments: [(Self.restingIPhone, CGFloat(3)), (Self.restingIPad, CGFloat(2))])
    func restingZoomStaysOnTheReducedTier(zoom: CGFloat, displayScale: CGFloat) {
        #expect(detail(zoom: zoom, displayScale: displayScale) == .overview)
    }

    /// L'autre moitié du marché, et la plus importante : **poser une épingle se
    /// fait sur les pixels natifs.**
    ///
    /// La visée `.place` cadre à `max(minimumZoomScale × 3, 1)` — soit 1,28 sur
    /// iPhone et 2,01 sur iPad, où le minimum est plus haut. C'est là que se
    /// soumettent les POI, donc c'est là que la netteté compte : un seuil qui
    /// laisserait ce zoom sur l'étage réduit annulerait tout l'intérêt d'avoir
    /// généré la carte à 8 192 px.
    @Test(arguments: [(Self.restingIPhone, CGFloat(3)), (Self.restingIPad, CGFloat(2))])
    func placementZoomEarnsTheNativeTier(resting: CGFloat, displayScale: CGFloat) {
        let placement = max(resting * 3, 1)
        #expect(detail(zoom: placement, displayScale: displayScale) == .full)
    }

    /// Et au zoom maximal, jamais autre chose que le natif — c'est le seul zoom
    /// où l'écart entre les deux étages a été VU.
    @Test(arguments: [CGFloat(2), CGFloat(3)])
    func maximumZoomAlwaysEarnsTheNativeTier(displayScale: CGFloat) {
        #expect(detail(zoom: 2.5, displayScale: displayScale) == .full)
    }

    /// L'hystérésis, prouvée par ce qui la distingue d'un simple seuil : le MÊME
    /// zoom ne donne pas le même étage selon d'où l'on vient.
    ///
    /// Sans elle, pincer autour du seuil ferait décoder puis libérer 256 Mo à
    /// chaque aller-retour — pendant le geste, c'est-à-dire au pire moment.
    @Test func theSameZoomKeepsWhicheverTierItCameFrom() {
        // Juste sous le seuil de montée (6 144 px / 3 / 2 048 = 1,0).
        let between: CGFloat = 0.95
        #expect(detail(zoom: between, displayScale: 3, from: .overview) == .overview)
        #expect(detail(zoom: between, displayScale: 3, from: .full) == .full)
    }

    /// Mais l'hystérésis ne doit pas non plus être un cliquet : assez loin sous le
    /// seuil, on redescend. Sinon les 192 Mo d'écart resteraient acquis pour toute
    /// la session dès le premier pincement.
    @Test func comingBackDownFarEnoughReleasesTheNativeTier() {
        #expect(detail(zoom: Self.restingIPhone, displayScale: 3, from: .full) == .overview)
        #expect(detail(zoom: Self.restingIPad, displayScale: 2, from: .full) == .overview)
    }

    /// La géométrie sur laquelle tout repose, isolée : ce que l'écran peut montrer
    /// de l'image. Le reste du fichier n'est vrai que si celle-ci l'est.
    @Test func displayablePixelsAreContentTimesZoomTimesScale() {
        #expect(
            MapArtDetailSelector.displayablePixels(zoomScale: 0.427, contentSize: 2048, displayScale: 3)
                .rounded() == 2623
        )
        // L'échelle d'écran ne descend jamais sous 1, et un zoom négatif n'existe
        // pas : les deux bornes évitent qu'une valeur aberrante fasse choisir
        // l'étage natif à l'envers.
        #expect(MapArtDetailSelector.displayablePixels(zoomScale: 1, contentSize: 2048, displayScale: 0) == 2048)
        #expect(MapArtDetailSelector.displayablePixels(zoomScale: -1, contentSize: 2048, displayScale: 3) == 0)
    }
}
