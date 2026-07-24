import SwiftUI
import UIKit

/// Moteur de la carte — seule pièce UIKit (UIScrollView : pas d'équivalent
/// SwiftUI pour zoom/pan momentum natif). Le contenu zoomé lui-même (image +
/// tous les pins) est une unique vue SwiftUI hébergée via UIHostingController
/// — parce qu'UIScrollView applique son transform de zoom/pan directement à
/// cette vue hébergée, les pins bougent AVEC la carte, sur la même horloge :
/// plus de décalage d'une frame comme avec l'ancien design (pins en overlay
/// SwiftUI séparé, repositionnés via un @State poussé depuis
/// scrollViewDidScroll — la carte bouge côté render server, les pins
/// rattrapaient une frame plus tard côté main thread). CLAUDE.md : "UIKit
/// seulement si une API l'impose, wrapped in one file" — tout le moteur
/// (scroll view + contenu hébergé) reste dans ce seul fichier.

/// Charge l'image de carte plate une seule fois — l'image entière (~500 Ko)
/// tient largement en mémoire, donc pas besoin de streaming par tuiles.
private enum MapArtLoader {
    static let image: UIImage? = {
        guard let url = Bundle.main.url(forResource: "island", withExtension: "png", subdirectory: "MapArt") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()
}

/// Contenu SwiftUI hébergé — l'image de la carte plus tous les pins, en
/// coordonnées de contenu plein-résolution (indépendantes du zoom/pan
/// courant, voir `MapGeometry.contentPoint`). `zoomScale` n'est utilisé QUE
/// pour garder les pins à une taille visuelle constante à l'écran
/// (contre-échelle 1/zoomScale) — jamais pour repositionner quoi que ce soit.
private struct MapContentSwiftUIView: View {
    let manifest: MapManifest
    let pois: [POI]
    let personalPins: [PersonalPin]
    let communitySpots: [Contribution]
    let isFound: (POI) -> Bool
    var zoomScale: CGFloat = 1
    let onTapPOI: (POI) -> Void
    let onVote: (Contribution, VoteDirection) -> Void
    let onReport: (Contribution) -> Void
    let onBlockAuthor: (Contribution) -> Void

    private var fullSize: CGFloat { MapGeometry.fullSize(for: manifest) }
    private var pinScale: CGFloat { 1 / max(zoomScale, 0.01) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let mapImage = MapArtLoader.image {
                Image(uiImage: mapImage)
                    .resizable()
                    .frame(width: fullSize, height: fullSize)
            }
            ForEach(pois) { poi in
                if let position = poi.position {
                    poiPin(poi, at: position)
                }
            }
            ForEach(personalPins) { pin in
                personalPin(pin)
            }
            ForEach(communitySpots) { spot in
                ContributionAnnotationView(
                    spot: spot,
                    onVote: { direction in onVote(spot, direction) },
                    onReport: { onReport(spot) },
                    onBlockAuthor: { onBlockAuthor(spot) }
                )
                .scaleEffect(pinScale)
                .position(MapGeometry.contentPoint(for: spot.position, manifest: manifest))
            }
        }
        .frame(width: fullSize, height: fullSize)
    }

    private func poiPin(_ poi: POI, at position: NormalizedPoint) -> some View {
        let found = isFound(poi)
        return Button {
            onTapPOI(poi)
        } label: {
            Image(systemName: found ? "checkmark.circle.fill" : "mappin.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(found ? NCColor.neonCyan.opacity(0.4) : NCColor.neonCyan)
                .shadow(color: NCColor.neonCyan.opacity(found ? 0.2 : 0.6), radius: 4)
        }
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: position, manifest: manifest))
        .accessibilityLabel(Text(poi.title.resolved(for: Self.currentLanguageCode)))
    }

    private func personalPin(_ pin: PersonalPin) -> some View {
        Image(systemName: "star.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(NCColor.sunsetOrange)
            .scaleEffect(pinScale)
            .position(MapGeometry.contentPoint(for: NormalizedPoint(x: pin.x, y: pin.y), manifest: manifest))
            .accessibilityLabel(Text(pin.title))
    }

    private static var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}

/// Calcule et applique un zoom/centrage adapté au viewport réel une fois les
/// bounds connus — voir les plans UX-polish (rounds 1 et 2) pour l'historique
/// complet de cette logique fit/cover/center ; INCHANGÉE par ce plan.
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

        let containScale = MapGeometry.fitZoomScale(contentSize: contentNativeSize, in: bounds.size)
        minimumZoomScale = containScale

        if !hasPerformedInitialFit {
            hasPerformedInitialFit = true
            let coverScale = MapGeometry.coverZoomScale(contentSize: contentNativeSize, in: bounds.size)
            zoomScale = coverScale
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: coverScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            contentOffset = MapGeometry.centeredContentOffset(contentSize: contentNativeSize, zoomScale: coverScale, in: bounds.size)
        } else {
            zoomScale = max(zoomScale, minimumZoomScale)
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: zoomScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        }
    }
}

struct TiledMapRepresentable: UIViewRepresentable {
    let manifest: MapManifest
    let pois: [POI]
    let personalPins: [PersonalPin]
    let communitySpots: [Contribution]
    let isFound: (POI) -> Bool
    @Binding var viewport: MapViewport
    let onLongPress: (CGPoint) -> Void
    let onTapPOI: (POI) -> Void
    let onVote: (Contribution, VoteDirection) -> Void
    let onReport: (Contribution) -> Void
    let onBlockAuthor: (Contribution) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: $viewport, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = FitToBoundsScrollView()
        // Le moteur gère lui-même son centrage entier via contentInset
        // calculé (voir FitToBoundsScrollView.layoutSubviews) — laisser le
        // système empiler en plus les safe-area insets (comportement
        // .automatic par défaut) rendrait la position de repos asymétrique.
        scrollView.contentInsetAdjustmentBehavior = .never
        let fullSize = MapGeometry.fullSize(for: manifest)

        let hostingController = UIHostingController(rootView: makeContent(zoomScale: 1))
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(x: 0, y: 0, width: fullSize, height: fullSize)

        scrollView.contentSize = hostingController.view.frame.size
        scrollView.contentNativeSize = hostingController.view.frame.size
        scrollView.addSubview(hostingController.view)
        // Plus de plafond à 1 imposé par une pyramide CATiledLayer — une
        // image directe peut être zoomée au-delà de sa résolution native
        // avec une interpolation acceptable, ce qui rend la carte réellement
        // explorable plutôt que statique une fois entièrement affichée.
        scrollView.maximumZoomScale = 2.5
        scrollView.delegate = context.coordinator
        context.coordinator.contentView = hostingController.view
        context.coordinator.hostingController = hostingController
        scrollView.backgroundColor = .black

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

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Rafraîchit les données (pois/personalPins/communitySpots) sans
        // écraser le zoomScale que `Coordinator.sync` maintient déjà en
        // direct sur chaque frame de scroll/zoom — on relit le zoomScale
        // courant du rootView plutôt que d'en repartir de 1.
        let currentZoom = context.coordinator.hostingController?.rootView.zoomScale ?? viewport.zoomScale
        context.coordinator.hostingController?.rootView = makeContent(zoomScale: currentZoom)
    }

    private func makeContent(zoomScale: CGFloat) -> MapContentSwiftUIView {
        MapContentSwiftUIView(
            manifest: manifest,
            pois: pois,
            personalPins: personalPins,
            communitySpots: communitySpots,
            isFound: isFound,
            zoomScale: zoomScale,
            onTapPOI: onTapPOI,
            onVote: onVote,
            onReport: onReport,
            onBlockAuthor: onBlockAuthor
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var contentView: UIView?
        fileprivate var hostingController: UIHostingController<MapContentSwiftUIView>?
        @Binding private var viewport: MapViewport
        private let onLongPress: (CGPoint) -> Void

        init(viewport: Binding<MapViewport>, onLongPress: @escaping (CGPoint) -> Void) {
            _viewport = viewport
            self.onLongPress = onLongPress
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { sync(scrollView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { sync(scrollView) }

        fileprivate func sync(_ scrollView: UIScrollView) {
            let newViewport = MapViewport(zoomScale: scrollView.zoomScale, contentOffset: scrollView.contentOffset)
            viewport = newViewport
            // Poussé directement ici (pas via updateUIView) : ce chemin
            // s'exécute sur CHAQUE frame de scroll/zoom, donc c'est le point
            // le moins coûteux pour garder les pins à taille constante à
            // l'écran (contre-échelle) sans dépendre d'un aller-retour par
            // SwiftUI côté MapScreen.
            hostingController?.rootView.zoomScale = newViewport.zoomScale
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let contentView else { return }
            onLongPress(gesture.location(in: contentView))
        }
    }
}
