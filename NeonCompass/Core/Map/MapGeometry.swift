import CoreGraphics

/// État de zoom/pan de l'UIScrollView, poussé par TiledMapRepresentable
/// (Task 5) vers la couche SwiftUI pour positionner pins et overlays.
struct MapViewport: Equatable, Sendable {
    var zoomScale: CGFloat = 1
    var contentOffset: CGPoint = .zero
}

enum MapGeometry {
    static func fullSize(for manifest: TileManifest) -> CGFloat {
        CGFloat(manifest.tileSize * (1 << manifest.maxZoom))
    }

    static func screenPosition(for point: NormalizedPoint, manifest: TileManifest, viewport: MapViewport) -> CGPoint {
        let full = fullSize(for: manifest)
        return CGPoint(
            x: CGFloat(point.x) * full * viewport.zoomScale - viewport.contentOffset.x,
            y: CGFloat(point.y) * full * viewport.zoomScale - viewport.contentOffset.y
        )
    }

    /// `point` est en coordonnées du canvas UIKit plein-résolution (Task 5),
    /// pas du viewport visible — indépendant du zoom/pan courant.
    static func normalizedPoint(fromCanvasPoint point: CGPoint, manifest: TileManifest) -> NormalizedPoint {
        let full = fullSize(for: manifest)
        return NormalizedPoint(x: Double(point.x / full), y: Double(point.y / full))
    }
}
