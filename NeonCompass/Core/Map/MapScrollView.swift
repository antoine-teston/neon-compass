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

/// Tout ce que le contenu de carte retient du zoom ET du panoramique — et rien
/// de plus.
///
/// Le zoom brut change à CHAQUE frame de pincement, et le contenu le stockait
/// tel quel : la moindre variation faisait donc réévaluer le corps de la vue et
/// reconstruire toutes les pastilles, alors que le rendu, lui, ne dépend que de
/// fonctions EN ESCALIER de la position de la vue :
///
/// - `pinScale`, plafonnée à 1 — donc constante sur toute la plage sous le zoom
///   neutre, c'est-à-dire précisément au dézoom maximal ;
/// - `clusterShape`, quantifiée en demi-octaves — donc constante entre deux
///   paliers ;
/// - `window`, quantifiée sur une grille de tuiles mesurées À L'ÉCRAN — donc
///   constante tant qu'on ne franchit pas une tuile, à une cadence qui ne
///   dépend pas du zoom (voir `MapRenderWindow`).
///
/// En ne retenant que celles-là, la valeur de la vue reste identique d'une
/// frame à l'autre et SwiftUI saute le corps. `Equatable` est ce qui lui permet
/// de le constater.
struct MapRenderState: Equatable {
    var pinScale: CGFloat
    var clusterShape: MapClusterer.Shape
    /// Seule composante qui dépende aussi du PANORAMIQUE. C'est un compromis
    /// assumé : le panoramique, jusqu'ici gratuit en réévaluations, en paie
    /// désormais une par tuile franchie — mais chacune est bien moins chère,
    /// puisqu'elle ne bâtit plus que les pastilles visibles.
    var window: MapRenderWindow

    init(zoomScale: CGFloat, contentSize: CGFloat, window: MapRenderWindow = .whole) {
        // Contre-échelle pour garder les pins à taille écran constante, mais
        // PLAFONNÉE à 1 : sans ce plafond, une carte dézoomée à 0,43 gonflait
        // chaque pin à ~51 pt (22 × 1/0,43) et la fixture de référence noyait
        // entièrement la carte sous les pastilles.
        pinScale = min(1 / max(zoomScale, 0.01), 1)
        clusterShape = MapClusterer.shape(zoomScale: zoomScale, contentSize: contentSize)
        self.window = window
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
    /// Toujours vide en Release : le mode éditeur n'existe pas dans le binaire
    /// soumis. C'est ce qui évite un `#if DEBUG` dans le moteur de carte.
    let draftPins: [DraftPin]
    /// Clés d'invalidation de `MapClusterCache`, portées par les modèles
    /// propriétaires des deux collections. Voir `MapClusterCache`.
    let poisGeneration: Int
    let spotsGeneration: Int
    /// L'ensemble lui-même, et non plus un prédicat `(POI) -> Bool`.
    ///
    /// Une fermeture n'est pas comparable : tant que l'état « trouvé » entrait
    /// par là, le moteur ne pouvait pas savoir qu'il avait changé autrement qu'en
    /// faisant avancer la génération des POI — ce qui périmait le cache de
    /// groupes et rebâtissait les cinq cent trente-sept points pour un seul
    /// marquage. Un `Set` est `Equatable`, donc l'invalidation devient exacte.
    let foundPOIIDs: Set<String>
    var zoom: MapRenderState
    let onTapPOI: (POI) -> Void
    let onTapCluster: (POICluster) -> Void
    /// Reçoit la position plutôt que le groupe : zoomer n'a besoin que d'un
    /// point, et les deux familles de pastilles portent des types différents.
    let onTapCommunityCluster: (NormalizedPoint) -> Void
    let onVote: (Contribution, VoteDirection) -> Void
    let onReport: (Contribution) -> Void
    let onBlockAuthor: (Contribution) -> Void
    /// Nil hors mode éditeur — donc toujours nil en Release, où l'éditeur
    /// n'existe pas. Même parti pris que `draftPins`.
    var onAdopt: ((Contribution) -> Void)?

    private var fullSize: CGFloat { MapGeometry.fullSize(for: manifest) }

    private var pinScale: CGFloat { zoom.pinScale }

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
            ForEach(visiblePersonalPins) { pin in
                personalPin(pin)
            }
            ForEach(communityClusters) { cluster in
                if let spot = cluster.single {
                    contributionAnnotation(spot)
                        .scaleEffect(pinScale)
                        .position(MapGeometry.contentPoint(for: spot.position, manifest: manifest))
                } else {
                    communityBubble(cluster)
                }
            }
            ForEach(visibleDraftPins) { pin in
                draftPin(pin)
            }
        }
        .frame(width: fullSize, height: fullSize)
    }

    private func communityBubble(_ cluster: ContributionCluster) -> some View {
        Button {
            onTapCommunityCluster(cluster.position)
        } label: {
            MapClusterBubbleView(
                count: cluster.count,
                category: cluster.dominantCategory,
                style: style,
                family: .community
            )
            .equatable()
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: cluster.position, manifest: manifest))
    }

    private func contributionAnnotation(_ spot: Contribution) -> some View {
        var view = ContributionAnnotationView(
            spot: spot,
            style: style,
            onVote: { direction in onVote(spot, direction) },
            onReport: { onReport(spot) },
            onBlockAuthor: { onBlockAuthor(spot) }
        )
#if DEBUG
        if let onAdopt {
            view.onAdopt = { onAdopt(spot) }
        }
#endif
        return view
    }

    /// Contour pointillé : un brouillon se distingue d'un POI publié au premier
    /// coup d'œil, ce qui est tout l'intérêt de l'afficher pendant la capture.
    /// Même cœur neutre que les épingles publiées — seul le trait change, sinon
    /// le brouillon serait la seule gommette pleine restante de la carte.
    private func draftPin(_ pin: DraftPin) -> some View {
        Image(systemName: POIPinPalette.symbol(for: pin.category))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(POIPinPalette.color(for: pin.category, style: style))
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(POIPinPalette.core(for: style).opacity(0.82))
                    .overlay(
                        Circle().strokeBorder(
                            POIPinPalette.color(for: pin.category, style: style),
                            style: StrokeStyle(lineWidth: 2, dash: [3, 2])
                        )
                    )
            )
            .scaleEffect(pinScale)
            .position(MapGeometry.contentPoint(for: pin.position, manifest: manifest))
            // `verbatim` : l'éditeur interne ne sort jamais du binaire de
            // debug, il n'a pas à peupler le catalogue des cinq langues — et
            // ce littéral s'y extrayait en souche vide.
            .accessibilityLabel(Text(verbatim: "Brouillon"))
    }

    /// Le découpage par fenêtre s'applique APRÈS le cache, jamais dedans : le
    /// cache reste indexé sur (famille, génération, forme), donc panoramiquer
    /// ne le périme pas. Filtrer 537 groupes coûte quelques centièmes de
    /// milliseconde, contre ~0,066 ms la pastille effectivement bâtie.
    private var clusters: [POICluster] {
        MapClusterCache.clusters(
            items: pois, shape: zoom.clusterShape,
            generation: poisGeneration
        ).filter { zoom.window.contains($0.position) }
    }

    /// Agrégés séparément des POI éditoriaux, et pas mêlés à eux : les deux
    /// familles ne se rendent pas pareil (état « trouvé » d'un côté, votes et
    /// signalement de l'autre) et n'ont pas la même autorité. Une pastille qui
    /// mélangerait les deux ne saurait pas dire ce qu'elle contient.
    ///
    /// Le préfixe d'identifiant est distinct : deux familles agrégées séparément
    /// tombent souvent dans la même cellule de grille, et sans lui leurs
    /// pastilles porteraient le même id — SwiftUI confondrait deux vues qui
    /// n'ont rien à voir.
    private var communityClusters: [ContributionCluster] {
        MapClusterCache.clusters(
            items: communitySpots, shape: zoom.clusterShape,
            keyPrefix: "s", generation: spotsGeneration
        ).filter { zoom.window.contains($0.position) }
    }

    /// Épingles personnelles et brouillons passent par la même fenêtre : ils
    /// sont peu nombreux aujourd'hui, mais rien ne garantit qu'ils le restent,
    /// et une exception silencieuse serait une régression en attente.
    private var visiblePersonalPins: [PersonalPin] {
        personalPins.filter { zoom.window.contains(NormalizedPoint(x: $0.x, y: $0.y)) }
    }

    private var visibleDraftPins: [DraftPin] {
        draftPins.filter { zoom.window.contains($0.position) }
    }

    /// Le `Button` est ICI et non dans `POIPinView` : la vue comparée doit rester
    /// pure valeur (cf. l'en-tête de `MapPinViews`). Seul le corps de l'épingle —
    /// le glyphe, l'anneau, le halo — est protégé par `.equatable()`, ce qui est
    /// exactement ce qui coûte.
    private func poiPin(_ poi: POI, at position: NormalizedPoint) -> some View {
        Button {
            onTapPOI(poi)
        } label: {
            POIPinView(
                category: poi.category,
                style: style,
                isFound: foundPOIIDs.contains(poi.id),
                accessibilityTitle: poi.title.resolved(for: Self.currentLanguageCode)
            )
            .equatable()
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: position, manifest: manifest))
    }

    private func clusterBubble(_ cluster: POICluster) -> some View {
        Button {
            onTapCluster(cluster)
        } label: {
            MapClusterBubbleView(
                count: cluster.count,
                category: cluster.dominantCategory,
                style: style,
                family: .editorial
            )
            .equatable()
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: cluster.position, manifest: manifest))
    }

    private func personalPin(_ pin: PersonalPin) -> some View {
        DroppedPinView(
            symbol: "star.fill",
            tint: NCColor.sunsetOrange,
            style: style,
            accessibilityTitle: pin.title
        )
        .equatable()
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: NormalizedPoint(x: pin.x, y: pin.y), manifest: manifest))
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
    var draftPins: [DraftPin] = []
    let poisGeneration: Int
    let spotsGeneration: Int
    let personalPinsGeneration: Int
    let foundPOIIDs: Set<String>
    @Binding var viewport: MapViewport
    let onLongPress: (CGPoint) -> Void
    let onTapPOI: (POI) -> Void
    let onVote: (Contribution, VoteDirection) -> Void
    let onReport: (Contribution) -> Void
    let onBlockAuthor: (Contribution) -> Void
    var onAdopt: ((Contribution) -> Void)?

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

        let hostingController = UIHostingController(rootView: makeContent(zoom: MapRenderState(zoomScale: 1, contentSize: fullSize), coordinator: context.coordinator))
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
        context.coordinator.contentFullSize = fullSize
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

    /// Tout ce qui, dans le contenu poussé vers la vue hébergée, peut changer.
    ///
    /// Le zoom et le panoramique n'en font PAS partie : ils sont poussés
    /// directement par `Coordinator.sync`, sur chaque frame, sans passer par ici.
    ///
    /// Les générations remplacent une comparaison de tableaux qui serait à la
    /// fois plus chère et FAUSSE : `POI` et `PersonalPin` sont des références,
    /// donc deux tableaux identiques peuvent porter des membres modifiés.
    struct ContentToken: Equatable {
        let game: MapGame
        let style: MapStyle
        let poisGeneration: Int
        let spotsGeneration: Int
        let personalPinsGeneration: Int
        let draftPins: [DraftPin]
        /// Comparé en entier, et c'est le point : marquer un lieu « trouvé » ne
        /// change NI la composition des groupes ni la liste filtrée (sauf sous
        /// « masquer les trouvés »), donc plus rien ne fait avancer la génération
        /// des POI dans ce cas. Sans cet ensemble ici, cocher un lieu ne
        /// repousserait aucun contenu et la coche n'apparaîtrait jamais.
        ///
        /// La comparaison est en O(n) sur des dizaines d'entrées, contre un
        /// recalcul des cinq cent trente-sept points qu'un compteur de génération
        /// aurait imposé.
        let foundPOIIDs: Set<String>
        /// L'éditeur armé change les gestes disponibles sans forcément changer
        /// les brouillons — sans ça, l'armer ne prendrait effet qu'au prochain
        /// changement de données.
        let canAdopt: Bool
    }

    private var contentToken: ContentToken {
        ContentToken(
            game: game,
            style: style,
            poisGeneration: poisGeneration,
            spotsGeneration: spotsGeneration,
            personalPinsGeneration: personalPinsGeneration,
            draftPins: draftPins,
            foundPOIIDs: foundPOIIDs,
            canAdopt: onAdopt != nil
        )
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
        // Rien de la carte n'a changé : ne pas repousser le contenu.
        //
        // Remplacer `rootView` fait reconstruire TOUTES les pastilles. Or
        // `updateUIView` est appelé pour quantité de raisons étrangères à la
        // carte — au premier chef l'ouverture et la fermeture d'une fiche de
        // POI, qui invalident le corps de l'écran sans toucher au contenu.
        // Mesuré sur iPhone : trois ouvertures et trois fermetures
        // provoquaient dix reconstructions complètes.
        let token = contentToken
        guard context.coordinator.displayedContent != token else { return }
        context.coordinator.displayedContent = token

        let currentZoom = context.coordinator.hostingController?.rootView.zoom ?? MapRenderState(zoomScale: viewport.zoomScale, contentSize: MapGeometry.fullSize(for: manifest))
        context.coordinator.hostingController?.rootView = makeContent(zoom: currentZoom, coordinator: context.coordinator)
    }

    private func makeContent(zoom: MapRenderState, coordinator: Coordinator) -> MapContentSwiftUIView {
        MapContentSwiftUIView(
            manifest: manifest,
            game: game,
            style: style,
            pois: pois,
            personalPins: personalPins,
            communitySpots: communitySpots,
            draftPins: draftPins,
            poisGeneration: poisGeneration,
            spotsGeneration: spotsGeneration,
            foundPOIIDs: foundPOIIDs,
            zoom: zoom,
            onTapPOI: onTapPOI,
            onTapCluster: { [weak coordinator] cluster in
                coordinator?.zoom(to: cluster.position, manifest: manifest)
            },
            onTapCommunityCluster: { [weak coordinator] position in
                coordinator?.zoom(to: position, manifest: manifest)
            },
            onVote: onVote,
            onReport: onReport,
            onBlockAuthor: onBlockAuthor,
            onAdopt: onAdopt
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
        /// Dernier jeton poussé — voir `TiledMapRepresentable.ContentToken`.
        fileprivate var displayedContent: TiledMapRepresentable.ContentToken?
        /// Côté du contenu en coordonnées pleine résolution. Retenu ici parce
        /// que `sync` en a besoin pour reconstruire l'état de zoom et n'a pas
        /// accès au manifeste.
        fileprivate var contentFullSize: CGFloat = 0
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
        func zoom(to clusterPosition: NormalizedPoint, manifest: MapManifest) {
            guard let scrollView, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            let target = min(scrollView.zoomScale * 2, scrollView.maximumZoomScale)
            guard target > scrollView.zoomScale else { return }
            let center = MapGeometry.contentPoint(for: clusterPosition, manifest: manifest)
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
            hostingController?.rootView.zoom = MapRenderState(
                zoomScale: newViewport.zoomScale,
                contentSize: contentFullSize,
                window: MapRenderWindow(
                    visibleContentRect: MapGeometry.visibleContentRect(
                        bounds: scrollView.bounds.size,
                        contentOffset: newViewport.contentOffset,
                        zoomScale: newViewport.zoomScale
                    ),
                    contentSize: contentFullSize,
                    zoomScale: newViewport.zoomScale
                )
            )
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let contentView else { return }
            onLongPress(gesture.location(in: contentView))
        }
    }
}
