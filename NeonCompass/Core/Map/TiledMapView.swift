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
        // minimumZoomScale is 1/2^maxZoom, so we need maxZoom reduced levels
        // below the normal-resolution level, i.e. levelsOfDetail = maxZoom + 1.
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

struct TiledMapRepresentable: UIViewRepresentable {
    let manifest: TileManifest
    @Binding var viewport: MapViewport
    let onLongPress: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: $viewport, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        let fullSize = MapGeometry.fullSize(for: manifest)
        let canvas = TiledCanvasView(manifest: manifest)
        canvas.frame = CGRect(x: 0, y: 0, width: fullSize, height: fullSize)
        scrollView.contentSize = canvas.frame.size
        scrollView.addSubview(canvas)
        scrollView.minimumZoomScale = 1 / CGFloat(1 << manifest.maxZoom)
        scrollView.maximumZoomScale = 1
        scrollView.delegate = context.coordinator
        context.coordinator.canvas = canvas
        scrollView.zoomScale = scrollView.minimumZoomScale
        scrollView.backgroundColor = .black

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

        private func sync(_ scrollView: UIScrollView) {
            viewport = MapViewport(zoomScale: scrollView.zoomScale, contentOffset: scrollView.contentOffset)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let canvas else { return }
            onLongPress(gesture.location(in: canvas))
        }
    }
}
