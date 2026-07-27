import CoreGraphics

/// État de zoom/pan de l'UIScrollView, poussé par TiledMapRepresentable
/// (Task 5) vers la couche SwiftUI pour positionner pins et overlays.
struct MapViewport: Equatable, Sendable {
    var zoomScale: CGFloat = 1
    var contentOffset: CGPoint = .zero
}

/// Symmetric margin needed to center scaled map content within a viewport —
/// `CoreGraphics`-only (no UIKit), so it stays unit-testable without a
/// simulator; `TiledMapView.swift` converts this to `UIEdgeInsets`.
struct ContentInsets: Equatable, Sendable {
    var top: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var right: CGFloat = 0
}

enum MapGeometry {
    static func fullSize(for manifest: MapManifest) -> CGFloat {
        CGFloat(manifest.size)
    }

    /// A point's position in content-space (full-resolution, un-zoomed) —
    /// ALL pin positioning needs now that pins live inside the same view the
    /// scroll view zooms/pans (see Plan: map-engine-rebuild). Deliberately
    /// takes no `MapViewport` — no `zoomScale`/`contentOffset` — because the
    /// content view's own transform IS the zoom/pan, applied uniformly to
    /// everything inside it, pins included.
    static func contentPoint(for point: NormalizedPoint, manifest: MapManifest) -> CGPoint {
        let full = fullSize(for: manifest)
        return CGPoint(x: CGFloat(point.x) * full, y: CGFloat(point.y) * full)
    }

    /// `point` est en coordonnées du canvas UIKit plein-résolution (Task 5),
    /// pas du viewport visible — indépendant du zoom/pan courant.
    static func normalizedPoint(fromCanvasPoint point: CGPoint, manifest: MapManifest) -> NormalizedPoint {
        let full = fullSize(for: manifest)
        return NormalizedPoint(x: Double(point.x / full), y: Double(point.y / full))
    }

    /// The zoom scale at which `contentSize` fits entirely within `bounds`
    /// (aspect-fit on the more constraining axis), never upscaled past 1 —
    /// this is a fully-zoomed-out map, not a photo that should ever render
    /// larger than its native pixel resolution. Returns 1 for degenerate
    /// (zero-sized) input rather than dividing by zero.
    static func fitZoomScale(contentSize: CGSize, in bounds: CGSize) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        return min(scale, 1)
    }

    /// The symmetric inset needed to center content of `contentSize` scaled
    /// by `zoomScale` within `bounds` — clamped to zero on any axis where the
    /// scaled content already fills or exceeds that axis of `bounds` (never
    /// negative).
    static func centeringInsets(contentSize: CGSize, zoomScale: CGFloat, in bounds: CGSize) -> ContentInsets {
        let scaledWidth = contentSize.width * zoomScale
        let scaledHeight = contentSize.height * zoomScale
        let horizontal = max((bounds.width - scaledWidth) / 2, 0)
        let vertical = max((bounds.height - scaledHeight) / 2, 0)
        return ContentInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    /// The zoom scale at which `contentSize` fills `bounds` completely on
    /// BOTH axes (cropping the excess on whichever axis has slack), rather
    /// than showing all of `contentSize` letterboxed — the "cover" analog of
    /// `fitZoomScale`'s "contain". Never upscaled past 1 for the same reason
    /// as `fitZoomScale`; returns 1 for degenerate (zero-sized) input.
    static func coverZoomScale(contentSize: CGSize, in bounds: CGSize) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        let scale = max(bounds.width / contentSize.width, bounds.height / contentSize.height)
        return min(scale, 1)
    }

    /// The `contentOffset` that centers content of `contentSize` scaled by
    /// `zoomScale` within `bounds`, on both axes independently — unlike
    /// `centeringInsets` (which only produces a valid *inset* for an axis
    /// where the scaled content is smaller than `bounds`, clamping to 0
    /// otherwise), this also correctly centers an axis where the scaled
    /// content EXCEEDS `bounds` (a "cover" crop) by returning a positive
    /// offset for that axis instead of leaving it pinned at 0.
    static func centeredContentOffset(contentSize: CGSize, zoomScale: CGFloat, in bounds: CGSize) -> CGPoint {
        let scaledWidth = contentSize.width * zoomScale
        let scaledHeight = contentSize.height * zoomScale
        return CGPoint(x: (scaledWidth - bounds.width) / 2, y: (scaledHeight - bounds.height) / 2)
    }
}
