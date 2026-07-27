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

    @Test func centeringInsetsClampToZeroWhenContentFillsOrExceedsAnAxis() {
        // Scaled content 500x500 exceeds both axes of a 300x400 viewport —
        // insets must clamp to 0, never go negative.
        let insets = MapGeometry.centeringInsets(
            contentSize: CGSize(width: 500, height: 500),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(insets == ContentInsets(top: 0, left: 0, bottom: 0, right: 0))
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
}
