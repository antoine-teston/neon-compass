import Testing
import CoreGraphics
@testable import NeonCompass

struct MapGeometryTests {
    let manifest = TileManifest(tileSize: 256, maxZoom: 3, tileCount: 85)

    @Test func fullSizeIsTileSizeTimesTwoPowMaxZoom() {
        #expect(MapGeometry.fullSize(for: manifest) == CGFloat(256 * 8))
    }

    @Test func screenPositionAtOriginNoZoomNoOffset() {
        let viewport = MapViewport(zoomScale: 1, contentOffset: .zero)
        let p = MapGeometry.screenPosition(for: NormalizedPoint(x: 0, y: 0), manifest: manifest, viewport: viewport)
        #expect(p == .zero)
    }

    @Test func screenPositionScalesWithZoomAndOffset() {
        let viewport = MapViewport(zoomScale: 0.5, contentOffset: CGPoint(x: 10, y: 20))
        let p = MapGeometry.screenPosition(for: NormalizedPoint(x: 0.5, y: 0.5), manifest: manifest, viewport: viewport)
        // fullSize = 2048 ; point brut = (1024, 1024) ; *0.5 zoom - offset
        #expect(p == CGPoint(x: 1024 * 0.5 - 10, y: 1024 * 0.5 - 20))
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
}
