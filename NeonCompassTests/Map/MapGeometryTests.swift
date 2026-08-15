import Testing
import CoreGraphics
@testable import NeonCompass

struct MapGeometryTests {
    let manifest = MapManifest(size: 2048)

    @Test func fullSizeMatchesTheManifestSize() {
        #expect(MapGeometry.fullSize(for: manifest) == 2048)
    }

    @Test func normalizedPointFromCanvasPointIsZoomIndependent() {
        // fullSize = 256 * 2^3 = 2048 — le canvas est plein-résolution,
        // donc cette conversion ne dépend d'aucun MapViewport.
        let point = MapGeometry.normalizedPoint(fromCanvasPoint: CGPoint(x: 1024, y: 512), manifest: manifest)
        #expect(abs(point.x - 0.5) < 0.0001)
        #expect(abs(point.y - 0.25) < 0.0001)
    }

    @Test func fitZoomScaleShrinksToFitTheSmallerDimension() {
        // contentSize 2048x2048, bounds 390x844 (iPhone-shaped) — width is
        // the binding constraint: 390/2048 < 844/2048.
        let scale = MapGeometry.fitZoomScale(contentSize: CGSize(width: 2048, height: 2048), in: CGSize(width: 390, height: 844))
        #expect(abs(scale - 390.0 / 2048.0) < 0.0001)
    }

    @Test func fitZoomScaleNeverUpscalesPastOne() {
        // Content smaller than the viewport must never be blown up past its
        // native resolution — this is a fully-zoomed-out map, not a photo.
        let scale = MapGeometry.fitZoomScale(contentSize: CGSize(width: 100, height: 100), in: CGSize(width: 390, height: 844))
        #expect(scale == 1)
    }

    @Test func fitZoomScaleIsOneForDegenerateInput() {
        #expect(MapGeometry.fitZoomScale(contentSize: .zero, in: CGSize(width: 390, height: 844)) == 1)
        #expect(MapGeometry.fitZoomScale(contentSize: CGSize(width: 2048, height: 2048), in: .zero) == 1)
    }

    @Test func centeringInsetsCentersSmallerContentOnBothAxes() {
        // Scaled content 200x200 inside a 300x400 viewport: 50pt horizontal
        // margin each side, 100pt vertical margin each side.
        let insets = MapGeometry.centeringInsets(
            contentSize: CGSize(width: 200, height: 200),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(insets == ContentInsets(top: 100, left: 50, bottom: 100, right: 50))
    }

    @Test func centeringInsetsFloorsToHalfBoundsPastRestWhenContentExceedsAnAxis() {
        // Scaled content 500x500 exceeds both axes of a 300x400 viewport, at
        // zoomScale 1 — past that pair's resting scale (coverZoomScale ==
        // 0.8), so the Task 10 overscroll plancher applies: bounds/2 on each
        // axis, not 0. Before that fix this clamped to zero, which pinned
        // scrolling on the image's edge and made a coastal pin uncenterable
        // once zoomed in (see overscrollAllowsCenteringAnyPoint).
        let insets = MapGeometry.centeringInsets(
            contentSize: CGSize(width: 500, height: 500),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(insets == ContentInsets(top: 200, left: 150, bottom: 200, right: 150))
    }

    @Test func centeringInsetsScalesContentSizeByZoomScale() {
        // contentSize 2048x2048 at zoomScale 0.2 -> scaled 409.6x409.6,
        // inside a 800x600 viewport: horizontal margin (800-409.6)/2=195.2,
        // vertical margin (600-409.6)/2=95.2.
        let insets = MapGeometry.centeringInsets(
            contentSize: CGSize(width: 2048, height: 2048),
            zoomScale: 0.2,
            in: CGSize(width: 800, height: 600)
        )
        #expect(abs(insets.left - 195.2) < 0.01)
        #expect(abs(insets.top - 95.2) < 0.01)
    }

    @Test("Tout point de la carte peut être amené au centre, même zoomé")
    func overscrollAllowsCenteringAnyPoint() {
        let content = CGSize(width: 2048, height: 2048)
        let bounds = CGSize(width: 402, height: 874)
        let insets = MapGeometry.centeringInsets(contentSize: content, zoomScale: 3.3, in: bounds)
        // Le coin supérieur gauche du contenu doit pouvoir atteindre le centre.
        #expect(insets.top >= bounds.height / 2)
        #expect(insets.left >= bounds.width / 2)
    }

    @Test func coverZoomScaleGrowsToFillTheLargerDimension() {
        // contentSize 2048x2048, bounds 390x844 (iPhone-shaped) — height is
        // the binding constraint this time (opposite of fitZoomScale, which
        // picks width): 844/2048 > 390/2048.
        let scale = MapGeometry.coverZoomScale(contentSize: CGSize(width: 2048, height: 2048), in: CGSize(width: 390, height: 844))
        #expect(abs(scale - 844.0 / 2048.0) < 0.0001)
    }

    /// Le plancher de zoom de la carte est l'échelle « cover » et non plus
    /// « contain » : c'est ce qui garantit qu'on ne peut jamais dézoomer
    /// jusqu'à faire apparaître des bandes vides autour de la carte. Vrai pour
    /// tout viewport non carré, et égal pour un viewport carré.
    @Test func coverIsNeverSmallerThanFitSoTheFloorLeavesNoLetterboxing() {
        let content = CGSize(width: 2048, height: 2048)
        for bounds in [CGSize(width: 402, height: 874),   // iPhone portrait
                       CGSize(width: 874, height: 402),   // paysage
                       CGSize(width: 1024, height: 1366), // iPad portrait
                       CGSize(width: 500, height: 500)] { // carré
            let fit = MapGeometry.fitZoomScale(contentSize: content, in: bounds)
            let cover = MapGeometry.coverZoomScale(contentSize: content, in: bounds)
            #expect(cover >= fit, "cover doit couvrir au moins autant que fit pour \(bounds)")
        }
    }

    /// À l'échelle de repos, la carte remplit les deux axes : aucun inset de
    /// centrage n'est nécessaire, donc aucune bande.
    @Test func restingScaleLeavesNoCenteringInsets() {
        let content = CGSize(width: 2048, height: 2048)
        let bounds = CGSize(width: 402, height: 874)
        let cover = MapGeometry.coverZoomScale(contentSize: content, in: bounds)
        let insets = MapGeometry.centeringInsets(contentSize: content, zoomScale: cover, in: bounds)
        #expect(insets == ContentInsets(top: 0, left: 0, bottom: 0, right: 0))
    }

    @Test func coverZoomScaleNeverUpscalesPastOne() {
        let scale = MapGeometry.coverZoomScale(contentSize: CGSize(width: 100, height: 100), in: CGSize(width: 390, height: 844))
        #expect(scale == 1)
    }

    @Test func coverZoomScaleIsOneForDegenerateInput() {
        #expect(MapGeometry.coverZoomScale(contentSize: .zero, in: CGSize(width: 390, height: 844)) == 1)
        #expect(MapGeometry.coverZoomScale(contentSize: CGSize(width: 2048, height: 2048), in: .zero) == 1)
    }

    @Test func centeredContentOffsetIsNegativeWhenContentFitsInsideTheViewport() {
        // Scaled content 200x200 inside a 300x400 viewport — matches the
        // negative, inset-driven offset a "contain" fit produces.
        let offset = MapGeometry.centeredContentOffset(
            contentSize: CGSize(width: 200, height: 200),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(offset == CGPoint(x: -50, y: -100))
    }

    @Test func centeredContentOffsetIsPositiveWhenContentIsCroppedByTheViewport() {
        // Scaled content 500x500 exceeds both axes of a 300x400 viewport —
        // must be a POSITIVE offset that centers the crop, not zero.
        let offset = MapGeometry.centeredContentOffset(
            contentSize: CGSize(width: 500, height: 500),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(offset == CGPoint(x: 100, y: 50))
    }

    @Test func contentPointAtOriginIsOrigin() {
        let point = MapGeometry.contentPoint(for: NormalizedPoint(x: 0, y: 0), manifest: manifest)
        #expect(point == .zero)
    }

    @Test func contentPointScalesByFullSizeOnly() {
        // manifest.size == 2048 (Task 1's fixture) — no zoom/offset involved.
        let point = MapGeometry.contentPoint(for: NormalizedPoint(x: 0.5, y: 0.25), manifest: manifest)
        #expect(point == CGPoint(x: 1024, y: 512))
    }

    @Test func contentPointAtBottomRightIsFullSize() {
        let point = MapGeometry.contentPoint(for: NormalizedPoint(x: 1, y: 1), manifest: manifest)
        #expect(point == CGPoint(x: 2048, y: 2048))
    }

    @Test func centeredContentOffsetForARealCoverFitScenario() {
        // The exact cover-fit scenario from coverZoomScaleGrowsToFillTheLargerDimension:
        // content 2048x2048 at scale 844/2048 -> scaled 844x844 exactly.
        // Width (844) exceeds the 390pt viewport (cropped, centered positive
        // offset); height (844) matches the 844pt viewport exactly (zero
        // offset, zero crop).
        let scale = 844.0 / 2048.0
        let offset = MapGeometry.centeredContentOffset(
            contentSize: CGSize(width: 2048, height: 2048),
            zoomScale: scale,
            in: CGSize(width: 390, height: 844)
        )
        #expect(abs(offset.x - 227) < 0.01)
        #expect(abs(offset.y - 0) < 0.01)
    }

    // MARK: - Fondu des bords

    /// Les deux appareils, à leur zoom de REPOS. Ce ne sont pas des mesures
    /// prises sur un simulateur : ce sont les tailles logiques des deux
    /// appareils visés, et le zoom de repos qui en découle (la carte couvre
    /// l'écran sans bande vide, donc `bounds.height / 2 048`).
    private static let phoneBounds = CGSize(width: 402, height: 874)
    private static let padBounds = CGSize(width: 1032, height: 1376)
    private static let mapSize = CGSize(width: 2048, height: 2048)

    /// Construit ce que la fenêtre voit quand la carte est CENTRÉE à ce zoom —
    /// la position de repos, et celle qu'on retrouve chaque fois qu'on n'a pas
    /// fait défiler. Passe par `visibleContentRect` plutôt que de poser un
    /// rectangle à la main, pour que le test parle de la même géométrie que le
    /// moteur.
    private static func centred(zoom: CGFloat, in bounds: CGSize) -> CGRect {
        MapGeometry.visibleContentRect(
            bounds: bounds,
            contentOffset: CGPoint(
                x: (2048 * zoom - bounds.width) / 2,
                y: (2048 * zoom - bounds.height) / 2
            ),
            zoomScale: zoom
        )
    }

    /// Au repos, aucun fondu — et ce n'est pas un réglage de confort.
    ///
    /// Le zoom de repos fait affleurer la carte à DEUX des quatre bords de
    /// l'écran, exactement. Un fondu toujours actif y poserait une vignette de
    /// 80 pt en haut et en bas, alors qu'au repos aucun fond n'est visible à
    /// côté de la carte : il n'y a rien à masquer.
    @Test func noFadeAtRestOnEitherDevice() {
        let phoneZoom = Self.phoneBounds.height / 2048
        let phone = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            visibleContentRect: Self.centred(zoom: phoneZoom, in: Self.phoneBounds),
            zoomScale: phoneZoom, displayScale: 3
        )
        #expect(phone.opacity == 0)
        let padZoom = Self.padBounds.height / 2048
        let pad = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            visibleContentRect: Self.centred(zoom: padZoom, in: Self.padBounds),
            zoomScale: padZoom, displayScale: 2
        )
        #expect(pad.opacity == 0)
    }

    /// Le défaut que ce tour corrige, et le test qui l'aurait attrapé.
    ///
    /// z = 0,68 sur iPad, c'est-à-dire huit millièmes au-dessus du repos : la
    /// carte ne dépasse l'écran que de 8,3 pt de chaque côté. L'ancienne
    /// formule en concluait « presque au repos » et rendait 0,10. Mais au-delà
    /// du repos l'encart vertical vaut une demi-fenêtre, donc le bord haut peut
    /// descendre à 688 pt du haut de l'écran : 688 pt de fond visible, une
    /// arête franche en travers, et un voile à 10 % pour la cacher.
    @Test func theFadeIsWholeWhenAnEdgeIsDraggedIn() {
        let zoom: CGFloat = 0.68
        let dragged = MapGeometry.visibleContentRect(
            bounds: Self.padBounds,
            contentOffset: CGPoint(x: (2048 * zoom - Self.padBounds.width) / 2, y: -688),
            zoomScale: zoom
        )
        let pad = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            visibleContentRect: dragged, zoomScale: zoom, displayScale: 2
        )
        #expect(pad.opacity == 1)
    }

    /// L'autre moitié du même arbitrage : au MÊME zoom, mais centrée, il ne se
    /// passe rien. C'est ce qui interdit à la correction de rendre le fondu
    /// permanent — une carte à peine plus grande que l'écran n'a pas de bord
    /// visible, donc pas de vignette.
    @Test func aMapBarelyLargerThanTheScreenStaysClean() {
        let pad = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            visibleContentRect: Self.centred(zoom: 0.68, in: Self.padBounds),
            zoomScale: 0.68, displayScale: 2
        )
        #expect(pad.opacity == 0)
    }

    /// Entre les deux, il entre en scène exactement à la vitesse à laquelle le
    /// fond se découvre : 40 pt de fond visible pour une bande de 80, soit la
    /// moitié.
    @Test func theFadeRampsWithHowMuchBackgroundShows() {
        let dragged = MapGeometry.visibleContentRect(
            bounds: Self.padBounds,
            contentOffset: CGPoint(x: (2048 - Self.padBounds.width) / 2, y: -40),
            zoomScale: 1
        )
        let pad = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            visibleContentRect: dragged, zoomScale: 1, displayScale: 2
        )
        #expect(abs(pad.opacity - 0.5) < 0.001)
    }

    /// Le fond découvert sur un côté suffit, même si les trois autres sont
    /// couverts — un seul calque sert les quatre bords, donc c'est le côté le
    /// plus découvert qui commande. Ici c'est la DROITE qui déborde.
    @Test func theMostUncoveredSideCommands() {
        let dragged = MapGeometry.visibleContentRect(
            bounds: Self.padBounds,
            contentOffset: CGPoint(x: 2048 - Self.padBounds.width + 120, y: 336),
            zoomScale: 1
        )
        let pad = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            visibleContentRect: dragged, zoomScale: 1, displayScale: 2
        )
        #expect(pad.opacity == 1)
    }

    /// Le cœur du chantier : 80 points d'ÉCRAN, à tous les zooms et sur les
    /// deux appareils. Le test refait le trajet dans l'autre sens — combien de
    /// points d'écran occupe la bande gravée, sachant l'échelle rendue — plutôt
    /// que de relire la formule qu'il vérifie. Une implémentation qui poserait
    /// la bande en points de CONTENU passerait le zoom 1 et échouerait partout
    /// ailleurs.
    @Test func theBandMeasuresEightyScreenPointsAtEveryZoom() {
        for (displayScale, bounds) in [(CGFloat(3), Self.phoneBounds), (CGFloat(2), Self.padBounds)] {
            let pixels = CGFloat(MapEdgeFadeImage.bandPixels(displayScale: displayScale))
            for zoom in [bounds.height / 2048, 1.0, 2.5, 3.3, 4.95] as [CGFloat] {
                let fade = MapGeometry.edgeFade(
                    band: MapEdgeFadeImage.band, contentSize: Self.mapSize,
                    visibleContentRect: Self.centred(zoom: zoom, in: bounds),
                    zoomScale: zoom, displayScale: displayScale
                )
                let onScreen = pixels / fade.contentsScale * zoom
                #expect(abs(onScreen - 80) < 0.01, "displayScale \(displayScale), zoom \(zoom)")
            }
        }
    }

    /// Un zoom nul est atteignable — `contentNativeSize` vaut zéro avant le
    /// premier `layoutSubviews`. Il ne doit produire ni infini ni NaN, et
    /// surtout pas de calque visible.
    @Test func aZeroZoomYieldsNothingVisibleRatherThanInfinity() {
        let fade = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            visibleContentRect: .zero, zoomScale: 0, displayScale: 2
        )
        #expect(fade.opacity == 0)
        #expect(fade.contentsScale > 0)
        #expect(fade.contentsScale.isFinite)
    }
}
