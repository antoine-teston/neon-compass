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

/// Charge les images de carte plates — pas de streaming par tuiles, une seule
/// image bornée.
///
/// UNE SEULE image en cache, délibérément : les cartes sont rendues à 4 096 px
/// pour limiter le flou au zoom maximal, ce qui fait ~67 Mo une fois
/// décompressée en mémoire. En garder trois (les deux habillages plus le
/// placeholder) immobiliserait 200 Mo dans une app qui héberge déjà Firebase et
/// la régie publicitaire — jetsam assuré. Le prix payé est un redécodage à
/// chaque bascule, c'est-à-dire sur une action volontaire et rare, jamais
/// pendant un geste.
///
/// `@MainActor` parce que le cache est un état mutable partagé et que seul
/// `body` (isolé MainActor) y touche.
@MainActor
private enum MapArtLoader {
    private static var cachedName: String?
    private static var cachedImage: UIImage?

    static func image(game: MapGame, style: MapStyle) -> UIImage? {
        let name = game.resourceName(style: style)
        if name == cachedName, let cachedImage { return cachedImage }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MapArt"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cachedName = name
        cachedImage = image
        return image
    }
}

/// Contenu SwiftUI hébergé — l'image de la carte plus tous les pins, en
/// coordonnées de contenu plein-résolution (indépendantes du zoom/pan
/// courant, voir `MapGeometry.contentPoint`). `zoomScale` n'est utilisé QUE
/// pour garder les pins à une taille visuelle constante à l'écran
/// (contre-échelle 1/zoomScale) — jamais pour repositionner quoi que ce soit.
private struct MapContentSwiftUIView: View {
    let manifest: MapManifest
    let game: MapGame
    let style: MapStyle
    let pois: [POI]
    let personalPins: [PersonalPin]
    let communitySpots: [Contribution]
    let isFound: (POI) -> Bool
    var zoomScale: CGFloat = 1
    let onTapPOI: (POI) -> Void
    let onTapCluster: (POICluster) -> Void
    let onVote: (Contribution, VoteDirection) -> Void
    let onReport: (Contribution) -> Void
    let onBlockAuthor: (Contribution) -> Void

    private var fullSize: CGFloat { MapGeometry.fullSize(for: manifest) }

    /// Contre-échelle pour garder les pins à taille écran constante, mais
    /// PLAFONNÉE à 1 : sans ce plafond, une carte dézoomée à 0,43 gonflait
    /// chaque pin à ~51 pt (22 × 1/0,43) et la fixture de référence noyait
    /// entièrement la carte sous les pastilles.
    private var pinScale: CGFloat { min(1 / max(zoomScale, 0.01), 1) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let mapImage = MapArtLoader.image(game: game, style: style) {
                Image(uiImage: mapImage)
                    .resizable()
                    // L'image est plus définie que l'espace de contenu (3 072 px
                    // pour 2 048 pt) : elle est donc RÉDUITE au repos et
                    // agrandie seulement au fort zoom. `.high` soigne les deux
                    // sens, là où l'interpolation par défaut crénelait la
                    // trame viaire fine à la réduction.
                    .interpolation(.high)
                    .frame(width: fullSize, height: fullSize)
            }
            ForEach(clusters) { cluster in
                if let poi = cluster.single, let position = poi.position {
                    poiPin(poi, at: position)
                } else {
                    clusterBubble(cluster)
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

    private var clusters: [POICluster] {
        POIClusterer.clusters(pois: pois, zoomScale: zoomScale, contentSize: fullSize)
    }

    private func poiPin(_ poi: POI, at position: NormalizedPoint) -> some View {
        let found = isFound(poi)
        let tint = POIPinPalette.color(for: poi.category, style: style)
        // La couleur de catégorie est le REMPLISSAGE, le glyphe est en négatif
        // dessus : à 26 pt, une pastille pleine se lit d'un coup d'œil, alors
        // qu'un symbole teinté sur fond sombre se réduit à un point flou.
        return Button {
            onTapPOI(poi)
        } label: {
            Image(systemName: found ? "checkmark" : POIPinPalette.symbol(for: poi.category))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(POIPinPalette.outline(for: style))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(tint.opacity(found ? 0.35 : 1))
                        .overlay(Circle().stroke(POIPinPalette.outline(for: style).opacity(0.55), lineWidth: 1))
                )
                .shadow(color: tint.opacity(found ? 0.15 : 0.5),
                        radius: POIPinPalette.glowRadius(for: style))
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: position, manifest: manifest))
        .accessibilityLabel(Text(poi.title.resolved(for: Self.currentLanguageCode)))
    }

    /// Pastille d'agrégation. Un tap zoome dessus plutôt que d'ouvrir une
    /// fiche : c'est le geste attendu, et c'est ce qui délie le groupe.
    private func clusterBubble(_ cluster: POICluster) -> some View {
        let tint = POIPinPalette.color(for: cluster.dominantCategory, style: style)
        return Button {
            onTapCluster(cluster)
        } label: {
            Text(cluster.count, format: .number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(POIPinPalette.outline(for: style))
                .padding(.horizontal, 7)
                .frame(minWidth: 30, minHeight: 30)
                .background(
                    Capsule()
                        .fill(tint)
                        .overlay(Capsule().stroke(POIPinPalette.outline(for: style).opacity(0.7), lineWidth: 1.5))
                )
                .shadow(color: tint.opacity(0.5), radius: POIPinPalette.glowRadius(for: style))
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: cluster.position, manifest: manifest))
        .accessibilityLabel(Text("map.cluster.accessibility \(cluster.count)"))
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

    /// Échelle de repos : la carte remplit l'écran sur les DEUX axes, sans
    /// bande vide. C'est aussi le plancher de zoom — on ne peut pas dézoomer
    /// en deçà, donc jamais de letterboxing.
    private func restingScale() -> CGFloat {
        MapGeometry.coverZoomScale(contentSize: contentNativeSize, in: bounds.size)
    }

    private func applyResting() {
        let scale = restingScale()
        minimumZoomScale = scale
        zoomScale = scale
        let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: scale, in: bounds.size)
        contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        contentOffset = MapGeometry.centeredContentOffset(contentSize: contentNativeSize, zoomScale: scale, in: bounds.size)
    }

    /// Ramène à l'état de repos, identique à celui du lancement. Appelé au
    /// changement de carte : les deux cartes n'ont ni la même emprise ni le
    /// même contenu, donc conserver le zoom/pan de la précédente laissait
    /// l'utilisateur au milieu de nulle part — au propre comme au figuré, on
    /// tombait sur un aplat uniforme.
    func refit() {
        guard bounds.width > 0, bounds.height > 0, contentNativeSize != .zero else { return }
        applyResting()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastFittedBoundsSize,
              bounds.width > 0, bounds.height > 0,
              contentNativeSize != .zero else { return }
        lastFittedBoundsSize = bounds.size

        // Plancher = échelle de repos, et non plus l'échelle « contain » :
        // pouvoir dézoomer jusqu'à voir tout le carré faisait apparaître des
        // bandes vides autour de la carte.
        minimumZoomScale = restingScale()

        if !hasPerformedInitialFit {
            hasPerformedInitialFit = true
            applyResting()
        } else {
            zoomScale = max(zoomScale, minimumZoomScale)
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: zoomScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        }
    }
}

struct TiledMapRepresentable: UIViewRepresentable {
    let manifest: MapManifest
    let game: MapGame
    let style: MapStyle
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

        let hostingController = UIHostingController(rootView: makeContent(zoomScale: 1, coordinator: context.coordinator))
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
        context.coordinator.scrollView = scrollView
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
        // Changement de carte : recadrer AVANT de pousser le nouveau contenu,
        // pour que les pins soient calculés avec le zoom d'arrivée.
        if context.coordinator.displayedGame != game {
            context.coordinator.displayedGame = game
            (scrollView as? FitToBoundsScrollView)?.refit()
        }
        let currentZoom = context.coordinator.hostingController?.rootView.zoomScale ?? viewport.zoomScale
        context.coordinator.hostingController?.rootView = makeContent(zoomScale: currentZoom, coordinator: context.coordinator)
    }

    private func makeContent(zoomScale: CGFloat, coordinator: Coordinator) -> MapContentSwiftUIView {
        MapContentSwiftUIView(
            manifest: manifest,
            game: game,
            style: style,
            pois: pois,
            personalPins: personalPins,
            communitySpots: communitySpots,
            isFound: isFound,
            zoomScale: zoomScale,
            onTapPOI: onTapPOI,
            onTapCluster: { [weak coordinator] cluster in
                coordinator?.zoom(to: cluster, manifest: manifest)
            },
            onVote: onVote,
            onReport: onReport,
            onBlockAuthor: onBlockAuthor
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var contentView: UIView?
        weak var scrollView: UIScrollView?
        fileprivate var hostingController: UIHostingController<MapContentSwiftUIView>?
        /// Dernière carte poussée dans la vue — sert à détecter un changement
        /// de carte dans `updateUIView`, qui est appelé pour bien d'autres
        /// raisons (chaque frame de scroll/zoom, notamment).
        fileprivate var displayedGame: MapGame?
        @Binding private var viewport: MapViewport
        private let onLongPress: (CGPoint) -> Void

        init(viewport: Binding<MapViewport>, onLongPress: @escaping (CGPoint) -> Void) {
            _viewport = viewport
            self.onLongPress = onLongPress
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

        /// Zoome sur un groupe pour le délier. Une octave par tap (deux
        /// paliers de `POIClusterer`, qui travaille en demi-octaves) : assez
        /// pour que le groupe se scinde réellement, pas assez pour perdre le
        /// contexte d'un coup.
        func zoom(to cluster: POICluster, manifest: MapManifest) {
            guard let scrollView, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            let target = min(scrollView.zoomScale * 2, scrollView.maximumZoomScale)
            guard target > scrollView.zoomScale else { return }
            let center = MapGeometry.contentPoint(for: cluster.position, manifest: manifest)
            let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
            scrollView.zoom(
                to: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height),
                animated: true
            )
        }

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
