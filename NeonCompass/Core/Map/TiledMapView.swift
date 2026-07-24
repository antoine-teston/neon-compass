import SwiftUI
import UIKit

/// Seule pièce UIKit du moteur de carte — CATiledLayer n'a pas d'équivalent
/// SwiftUI. Toute la logique zoom/pan/tuiles est isolée ici (CLAUDE.md :
/// "UIKit seulement si une API l'impose, wrapped in one file").

/// Tuile fixe utilisée pour dériver un pseudo-pyramide de zoom à partir de
/// l'image plate unique (Task 1 : docs/superpowers/plans/2026-07-24-
/// plan-map-engine-rebuild.md) — la vraie pyramide CATiledLayer a été
/// retirée avec `NeonCompass/Resources/MapTiles`. `TiledCanvasView` ci-dessous
/// est retiré en entier par Task 2 ; ceci ne fait que garder ce fichier
/// compilable entre-temps, plus de découpage réel en tuiles bundlées.
private let tilePyramidTileSize = 256

/// Charge l'image de carte plate bundlée (Task 1).
private enum TilePyramid {
    static func image(bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: "island", withExtension: "png", subdirectory: "MapArt") else {
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

    private let manifest: MapManifest

    init(manifest: MapManifest) {
        self.manifest = manifest
        super.init(frame: .zero)
        let tiled = layer as! CATiledLayer
        tiled.tileSize = CGSize(width: tilePyramidTileSize, height: tilePyramidTileSize)
        // levelsOfDetail = total pyramid levels (magnified + normal + reduced);
        // levelsOfDetailBias = how many of those are magnified (scale > 1).
        // maximumZoomScale is 1 here (no magnification), so bias stays 0;
        // minimumZoomScale is computed dynamically to fit the real viewport,
        // so we still need reduced levels below normal resolution, derived
        // from the flat image's size instead of a bundled tile pyramid depth
        // (Task 1 — Task 2 removes this CATiledLayer canvas entirely).
        tiled.levelsOfDetail = Self.maxZoom(for: manifest) + 1
        tiled.levelsOfDetailBias = 0
        contentScaleFactor = 1
        isOpaque = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private static func maxZoom(for manifest: MapManifest) -> Int {
        max(0, Int(log2(Double(manifest.size) / Double(tilePyramidTileSize))))
    }

    /// `draw(_:)` is invoked by `CATiledLayer` with the graphics context
    /// already clipped to the requested tile's `rect`, so drawing the whole
    /// flat image into the canvas' full bounds each call still only paints
    /// the clipped tile region — no per-tile image lookup needed since
    /// there's only one bundled image now (Task 1).
    nonisolated override func draw(_ rect: CGRect) {
        guard let image = TilePyramid.image() else { return }
        image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(manifest.size), height: CGFloat(manifest.size)))
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

        // minimumZoomScale always allows pinching all the way out to see the
        // ENTIRE map (aspect-fit / "contain") — the initial view below fills
        // the screen edge-to-edge instead, but the user can still zoom out
        // to this contain-scale at any time.
        let containScale = MapGeometry.fitZoomScale(contentSize: contentNativeSize, in: bounds.size)
        minimumZoomScale = containScale

        if !hasPerformedInitialFit {
            hasPerformedInitialFit = true
            // The initial view fills the whole screen edge-to-edge ("cover"),
            // cropping the excess on whichever axis has slack, instead of
            // shrinking to show the entire map letterboxed — a "contain"
            // start left nothing new to reveal by panning and nothing to
            // zoom out to (already at the minimum), which read as "the map
            // doesn't move." This gives real, immediate pan/zoom room from
            // the first frame.
            let coverScale = MapGeometry.coverZoomScale(contentSize: contentNativeSize, in: bounds.size)
            zoomScale = coverScale
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: coverScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            contentOffset = MapGeometry.centeredContentOffset(contentSize: contentNativeSize, zoomScale: coverScale, in: bounds.size)
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
    let manifest: MapManifest
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
