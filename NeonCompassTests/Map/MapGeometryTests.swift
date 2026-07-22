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
}
