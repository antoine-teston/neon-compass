import SwiftUI
import UIKit

/// Seule pièce UIKit du moteur de carte — CATiledLayer n'a pas d'équivalent
/// SwiftUI. Toute la logique zoom/pan/tuiles est isolée ici (CLAUDE.md :
/// "UIKit seulement si une API l'impose, wrapped in one file").

/// Charge une tuile PNG pré-rendue depuis le folder reference bundlé (Task 1).
private enum TilePyramid {
    static func image(z: Int, x: Int, y: Int, bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: "\(y)", withExtension: "png", subdirectory: "MapTiles/\(z)/\(x)") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

/// Vue support de CATiledLayer. Le niveau de zoom courant se lit dans la CTM
/// du contexte au moment de draw(_:) — technique standard pour afficher une
/// pyramide de tuiles pré-rendues (cf. l'échantillon Apple "PhotoScroller").
private final class TiledCanvasView: UIView {
    override class var layerClass: AnyClass { CATiledLayer.self }

    private let manifest: TileManifest

    init(manifest: TileManifest) {
        self.manifest = manifest
        super.init(frame: .zero)
        let tiled = layer as! CATiledLayer
        tiled.tileSize = CGSize(width: manifest.tileSize, height: manifest.tileSize)
        // levelsOfDetail = total pyramid levels (magnified + normal + reduced);
        // levelsOfDetailBias = how many of those are magnified (scale > 1).
        // maximumZoomScale is 1 here (no magnification), so bias stays 0;
        // minimumZoomScale is computed dynamically to fit the real viewport,
        // so we still need maxZoom reduced levels below normal resolution,
        // i.e. levelsOfDetail = maxZoom + 1.
        tiled.levelsOfDetail = manifest.maxZoom + 1
        tiled.levelsOfDetailBias = 0
        contentScaleFactor = 1
        isOpaque = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    nonisolated override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let scale = ctx.ctm.a
        guard scale > 0 else { return }
        let z = max(0, min(manifest.maxZoom, Int(round(log2(scale))) + manifest.maxZoom))
        let tileSizeInPoints = CGFloat(manifest.tileSize) / scale
        let x = Int(rect.origin.x / tileSizeInPoints)
        let y = Int(rect.origin.y / tileSizeInPoints)
        guard let image = TilePyramid.image(z: z, x: x, y: y) else { return }
        image.draw(in: rect)
    }
}

/// Computes and applies a fit-to-bounds zoom scale + centering inset once the
/// scroll view's real bounds are known — `minimumZoomScale`/`zoomScale` can't
/// be set correctly in `makeUIView` because SwiftUI hasn't laid the view out
/// yet at that point (bounds is still `.zero`). Only recomputes when
/// `bounds.size` genuinely changes (first layout, or a rotation) — never on
/// every layout pass, so it never fights a live pinch-zoom/pan gesture (those
/// change `zoomScale`/`contentOffset` directly without changing `bounds.size`,
/// so the guard below simply skips them).
private final class FitToBoundsScrollView: UIScrollView {
    var contentNativeSize: CGSize = .zero
    private var lastFittedBoundsSize: CGSize = .zero
    private var hasPerformedInitialFit = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastFittedBoundsSize,
              bounds.width > 0, bounds.height > 0,
              contentNativeSize != .zero else { return }
        lastFittedBoundsSize = bounds.size

        let fitScale = MapGeometry.fitZoomScale(contentSize: contentNativeSize, in: bounds.size)
        minimumZoomScale = fitScale

        if !hasPerformedInitialFit {
            hasPerformedInitialFit = true
            zoomScale = fitScale
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: fitScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            contentOffset = CGPoint(x: -insets.left, y: -insets.top)
        } else {
            // Bounds changed after the user may have already zoomed/panned
            // (e.g. iPad's POI detail side panel resizing the map's column,
            // or a rotation) — never yank zoom back to fit-scale here, only
            // keep the zoom range valid and re-center the inset margin so
            // any now-smaller-than-viewport content stays centered without
            // discarding the user's current zoomScale/contentOffset.
            zoomScale = max(zoomScale, minimumZoomScale)
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: zoomScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        }
    }
}

struct TiledMapRepresentable: UIViewRepresentable {
    let manifest: TileManifest
    @Binding var viewport: MapViewport
    let onLongPress: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: $viewport, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = FitToBoundsScrollView()
        // The map canvas manages its own centering entirely via computed
        // contentInset (see FitToBoundsScrollView.layoutSubviews) — letting
        // the system additionally stack safe-area insets on top (the
        // .automatic default) would make the resting position asymmetric.
        scrollView.contentInsetAdjustmentBehavior = .never
        let fullSize = MapGeometry.fullSize(for: manifest)
        let canvas = TiledCanvasView(manifest: manifest)
        canvas.frame = CGRect(x: 0, y: 0, width: fullSize, height: fullSize)
        scrollView.contentSize = canvas.frame.size
        scrollView.contentNativeSize = canvas.frame.size
        scrollView.addSubview(canvas)
        scrollView.maximumZoomScale = 1
        scrollView.delegate = context.coordinator
        context.coordinator.canvas = canvas
        scrollView.backgroundColor = .black
        // Deferred to the next run-loop turn: mutating the `@Binding var viewport`
        // synchronously here (still inside SwiftUI's makeUIView/update pass) is the
        // classic "modifying state during view update" hazard — sibling views in the
        // same ZStack (e.g. PersonalPinsOverlay/MapPinsOverlay) have already captured
        // the stale viewport for this render pass, and no further pass reliably picks
        // up the new value. Dispatching async lets this pass finish first, so the
        // resulting state change triggers a proper, fresh SwiftUI re-render.
        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.sync(scrollView)
        }

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        scrollView.addGestureRecognizer(longPress)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var canvas: UIView?
        @Binding private var viewport: MapViewport
        private let onLongPress: (CGPoint) -> Void

        init(viewport: Binding<MapViewport>, onLongPress: @escaping (CGPoint) -> Void) {
            _viewport = viewport
            self.onLongPress = onLongPress
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { sync(scrollView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { sync(scrollView) }

        fileprivate func sync(_ scrollView: UIScrollView) {
            viewport = MapViewport(zoomScale: scrollView.zoomScale, contentOffset: scrollView.contentOffset)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let canvas else { return }
            onLongPress(gesture.location(in: canvas))
        }
    }
}
