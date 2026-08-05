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
    /// Côté MAXIMAL d'une zone de frappe, dans l'espace de coordonnées des
    /// épingles : ce que valent ici les 44 pt d'écran du HIG.
    ///
    /// L'épingle dessinée fait 24 pt de contenu, et le contenu est réduit par la
    /// vue de défilement : au repos (≈0,43 sur iPhone, ≈0,67 sur iPad) elle ne
    /// mesure que ~10 pt à l'écran, moins d'un quart de la surface exigée. Grossir
    /// le DESSIN rendrait la carte illisible — c'est précisément ce que le plafond
    /// de `pinScale` évite. On grossit donc la seule zone de frappe.
    ///
    /// C'est un PLAFOND et non la valeur finale : chaque pastille est ensuite
    /// bornée par la distance à sa plus proche voisine, sans quoi les zones se
    /// recouvrent et le tap part sur la voisine (voir `MapPinMetrics.hitSides`).
    ///
    /// Le facteur est quantifié en demi-octaves, comme la forme des groupes : non
    /// quantifié il suivrait le zoom en continu et cette valeur changerait à chaque
    /// frame de pincement, ce qui ferait réévaluer tout le contenu — exactement ce
    /// que ce type existe pour empêcher.
    var pinHitCap: CGFloat
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
        // Ce que l'épingle mesure à l'écran vaut 24 × pinScale × zoomScale, soit
        // 24 × min(1, zoomScale) : au-dessus du zoom neutre la contre-échelle
        // annule l'agrandissement, en dessous le plafond laisse le dézoom rétrécir
        // le dessin. On divise donc 44 par ce même facteur.
        pinHitCap = MapPinMetrics.hitSide(
            forEffectiveScale: MapPinMetrics.quantizedEffectiveScale(zoomScale: zoomScale)
        )
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
    /// Le calque du carnet, masquable par la puce « Mes épingles » du panneau de
    /// filtres — les épingles échappaient jusqu'ici à tout filtre.
    let showPersonalPins: Bool
    let communitySpots: [Contribution]
    /// MES propositions pas encore publiques. Jamais groupées, contrairement aux
    /// spots communautaires : elles sont les miennes, elles se comptent sur les
    /// doigts.
    let myUnpublishedSpots: [Contribution]
    /// Toujours vide en Release : le mode éditeur n'existe pas dans le binaire
    /// soumis. C'est ce qui évite un `#if DEBUG` dans le moteur de carte.
    let draftPins: [DraftPin]
    /// Non nil pendant qu'on pose une proposition. Sa seule présence éteint la
    /// frappe de tout le reste du contenu.
    let placementPin: MapPlacementPin?
    /// Clés d'invalidation de `MapClusterCache`, portées par les modèles
    /// propriétaires des deux collections. Voir `MapClusterCache`.
    let poisGeneration: Int
    let spotsGeneration: Int
    /// L'ensemble lui-même, et non un prédicat `(POI) -> Bool` : une fermeture
    /// n'est pas comparable, donc le moteur ne pouvait pas savoir que l'état avait
    /// changé autrement qu'en faisant avancer la génération des POI — ce qui
    /// périmait le cache de groupes et réagrégeait les 537 points pour un seul
    /// marquage. Un `Set` est `Equatable`, donc l'invalidation devient exacte.
    let foundPOIIDs: Set<String>
    var zoom: MapRenderState
    let onTapPOI: (POI) -> Void
    let onTapPersonalPin: (PersonalPin) -> Void
    let onTapCluster: (POICluster) -> Void
    /// Reçoit la position plutôt que le groupe : zoomer n'a besoin que d'un
    /// point, et les deux familles de pastilles portent des types différents.
    let onTapCommunityCluster: (NormalizedPoint) -> Void
    let onReport: (Contribution) -> Void
    let onBlockAuthor: (Contribution) -> Void
    /// Nil hors mode éditeur — donc toujours nil en Release, où l'éditeur
    /// n'existe pas. Même parti pris que `draftPins`.
    var onAdopt: ((Contribution) -> Void)?

    private var fullSize: CGFloat { MapGeometry.fullSize(for: manifest) }

    private var pinScale: CGFloat { zoom.pinScale }

    var body: some View {
        // Calculé UNE fois par évaluation, jamais par pastille : le voisinage est
        // une propriété de l'ensemble, et le redemander à chaque épingle le ferait
        // payer deux cents fois.
        let hitSides = tappableHitSides
        return ZStack(alignment: .topLeading) {
            Group {
                mapBody(hitSides: hitSides)
            }
            // Tant qu'on pose une épingle, plus RIEN du contenu n'est tapable.
            //
            // Ce n'est pas de la prudence : le tap appartient alors au
            // reconnaisseur de placement, qui le lit comme « pose-la ici ». Sans
            // ça, viser un toit sur lequel se trouve un POI ouvrirait sa fiche —
            // un bouton SwiftUI répond au relâchement, et `cancelsTouchesInView`
            // arrive parfois trop tard pour l'en empêcher.
            .allowsHitTesting(placementPin == nil)

            if let placementPin {
                ghostPin(placementPin)
            }
        }
        .frame(width: fullSize, height: fullSize)
    }

    @ViewBuilder
    private func mapBody(hitSides: [String: CGFloat]) -> some View {
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
                    poiPin(poi, at: position, hitSide: hitSides[cluster.id] ?? zoom.pinHitCap)
                } else {
                    clusterBubble(cluster, hitSide: hitSides[cluster.id] ?? zoom.pinHitCap)
                }
            }
            if showPersonalPins {
                ForEach(visiblePersonalPins) { pin in
                    personalPin(pin, hitSide: hitSides[Self.hitKey(for: pin)] ?? zoom.pinHitCap)
                }
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
            // Dessinées APRÈS les spots communautaires, donc au-dessus : si
            // l'une des miennes vient d'être publiée et qu'un fragment en
            // retard la montre encore des deux côtés, c'est la mienne qu'on
            // voit — celle qui sait dire où elle en est.
            ForEach(visibleUnpublishedSpots) { spot in
                PendingContributionAnnotationView(spot: spot, style: style)
                    .scaleEffect(pinScale)
                    .position(MapGeometry.contentPoint(for: spot.position, manifest: manifest))
            }
            ForEach(visibleDraftPins) { pin in
                draftPin(pin)
            }
        }
    }

    /// L'épingle en cours de pose.
    ///
    /// Elle vit DANS le contenu hébergé et non en calque au-dessus de la vue de
    /// défilement — l'en-tête de ce fichier dit pourquoi : un calque repositionné
    /// depuis `scrollViewDidScroll` rattrape la carte avec une frame de retard.
    /// C'est le design que ce moteur a mesuré puis abandonné.
    ///
    /// Même vocabulaire que `draftPin` : ce qui n'est pas encore publié porte un
    /// anneau pointillé. Ce qui la distingue est sa taille et son halo — elle est
    /// le sujet de l'écran tant qu'on la pose.
    ///
    /// Insensible aux gestes : ce sont les deux reconnaisseurs UIKit du
    /// coordinateur qui la déplacent, parce qu'un geste SwiftUI posé ici
    /// perdrait l'arbitrage contre le panoramique de la vue de défilement.
    private func ghostPin(_ pin: MapPlacementPin) -> some View {
        let tint = POIPinPalette.color(for: pin.category, style: style)
        return Image(systemName: POIPinPalette.symbol(for: pin.category))
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(POIPinPalette.core(for: style).opacity(0.9))
                    .overlay(
                        Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                    )
                    .shadow(color: tint.opacity(0.7), radius: 6)
            )
            .scaleEffect(pinScale)
            .position(MapGeometry.contentPoint(for: pin.position, manifest: manifest))
            // Le saut d'un tap devient un déplacement qu'on suit des yeux. Sans
            // ça, l'épingle se téléporte et on doute d'avoir touché la bonne
            // chose.
            .animation(.snappy(duration: 0.18), value: pin.position)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func communityBubble(_ cluster: ContributionCluster) -> some View {
        Button {
            onTapCommunityCluster(cluster.position)
        } label: {
            MapClusterBubbleView(
                // Une proposition de joueur n'a pas d'état « trouvé » : elle n'est
                // pas dans la progression, donc son anneau reste plein.
                count: cluster.count,
                foundCount: 0,
                category: cluster.dominantCategory,
                style: style,
                family: .community
            )
            .equatable()
            .pinHitArea(side: zoom.pinHitCap)
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: cluster.position, manifest: manifest))
    }

    private func contributionAnnotation(_ spot: Contribution) -> some View {
        var view = ContributionAnnotationView(
            spot: spot,
            style: style,
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

    /// Côté de la zone de frappe, indexé par identifiant, pour TOUT ce qui se tape
    /// et ouvre une fiche : groupes éditoriaux ET épingles personnelles.
    ///
    /// Les deux familles passent dans le MÊME balayage depuis que l'épingle est
    /// tapable. Le commentaire précédent justifiait de l'exclure par le fait
    /// qu'elle « ne se tape pas du tout » — une épingle posée à côté d'un lieu lui
    /// volerait désormais ses taps avec ses 44 pt. L'argument de non-recouvrement
    /// est géométrique, il ne connaît pas les familles.
    ///
    /// Les pastilles communautaires restent dehors, comme avant : elles sont rares
    /// — il n'y en a aucune sur la carte de référence — et portent leur propre
    /// surface interactive. Les brouillons non plus ne se tapent pas.
    ///
    /// Recalculé à chaque évaluation du corps, mais le balayage s'arrête au-delà du
    /// plafond en abscisse : chaque pastille ne compare qu'avec ses quelques
    /// voisines immédiates, pas avec les deux cents autres.
    private var tappableHitSides: [String: CGFloat] {
        let visibleClusters = clusters
        let visiblePins = visiblePersonalPins
        let points = visibleClusters.map { MapGeometry.contentPoint(for: $0.position, manifest: manifest) }
            + visiblePins.map { MapGeometry.contentPoint(for: $0.position, manifest: manifest) }
        let sides = MapPinMetrics.hitSides(for: points, cap: zoom.pinHitCap)
        // Préfixe distinct : un groupe et une épingle peuvent porter le même
        // identifiant de cellule, et sans lui l'une écraserait l'autre dans le
        // dictionnaire.
        let ids = visibleClusters.map(\.id) + visiblePins.map { Self.hitKey(for: $0) }
        return Dictionary(uniqueKeysWithValues: zip(ids, sides))
    }

    private static func hitKey(for pin: PersonalPin) -> String { "p\(pin.id.uuidString)" }

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
    ///
    /// Le filtrage par CARTE, lui, se fait en amont (`PersonalPinStore.pins(for:)`) :
    /// le moteur ne reçoit que les épingles de la carte affichée.
    private var visiblePersonalPins: [PersonalPin] {
        personalPins.filter { zoom.window.contains($0.position) }
    }

    private var visibleDraftPins: [DraftPin] {
        draftPins.filter { zoom.window.contains($0.position) }
    }

    /// Même fenêtre que les deux précédentes, pour la même raison : elles sont
    /// peu nombreuses aujourd'hui, et une exception silencieuse serait une
    /// régression en attente.
    private var visibleUnpublishedSpots: [Contribution] {
        myUnpublishedSpots.filter { zoom.window.contains($0.position) }
    }

    /// Le `Button` est ICI et non dans `POIPinView` : la vue comparée doit rester
    /// pure valeur (cf. l'en-tête de `MapPinViews`). Seul le corps de l'épingle —
    /// le glyphe, l'anneau, le halo — est protégé par `.equatable()`, ce qui est
    /// exactement ce qui coûte.
    private func poiPin(_ poi: POI, at position: NormalizedPoint, hitSide: CGFloat) -> some View {
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
            .pinHitArea(side: hitSide)
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: position, manifest: manifest))
    }

    private func clusterBubble(_ cluster: POICluster, hitSide: CGFloat) -> some View {
        Button {
            onTapCluster(cluster)
        } label: {
            MapClusterBubbleView(
                count: cluster.count,
                foundCount: foundCount(in: cluster),
                category: cluster.dominantCategory,
                style: style,
                family: .editorial
            )
            .equatable()
            .pinHitArea(side: hitSide)
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: cluster.position, manifest: manifest))
    }

    /// Combien de membres du groupe sont déjà trouvés. Balaye les membres du seul
    /// groupe concerné, soit au total un passage sur les POI dessinés — négligeable
    /// devant ce que coûte une pastille bâtie, et c'est ce qui permet à
    /// `.equatable()` de ne rebâtir QUE le groupe dont le décompte a changé.
    private func foundCount(in cluster: POICluster) -> Int {
        guard !foundPOIIDs.isEmpty else { return 0 }
        return cluster.members.count { foundPOIIDs.contains($0.id) }
    }

    /// Le `Button` est ICI et non dans `DroppedPinView` : la vue comparée doit
    /// rester pure valeur (cf. l'en-tête de `MapPinViews`) — une fermeture n'est ni
    /// comparable ni `Sendable`, et sa seule présence ferait échouer la conformité
    /// à `Equatable` sous concurrence stricte.
    ///
    /// Toute la famille partage la teinte `sunsetOrange` : c'est le GLYPHE qui
    /// distingue une épingle d'une autre, parce que la palette néon appartient aux
    /// catégories éditoriales et que la lecture « telle couleur = telle
    /// catégorie » est ce qui rend la carte lisible.
    private func personalPin(_ pin: PersonalPin, hitSide: CGFloat) -> some View {
        Button {
            onTapPersonalPin(pin)
        } label: {
            DroppedPinView(
                symbol: pin.iconValue.symbol,
                tint: NCColor.sunsetOrange,
                style: style,
                isDone: pin.isDone,
                accessibilityTitle: pin.title.isEmpty ? String(localized: "map.pins.untitled") : pin.title
            )
            .equatable()
            .pinHitArea(side: hitSide)
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: pin.position, manifest: manifest))
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

/// Demande de recentrage sur un point, émise par le carnet et consommée une
/// seule fois par le moteur.
///
/// L'identifiant est ce qui la rend CONSOMMABLE : viser deux fois la même
/// épingle doit recentrer deux fois, or deux requêtes de même position seraient
/// égales et la seconde passerait pour déjà traitée.
/// L'épingle qu'on est en train de poser — position et catégorie, rien d'autre.
///
/// La catégorie en fait partie parce que la pastille change de couleur en
/// direct : c'est la seule confirmation qu'on a choisi la bonne dans le panneau.
struct MapPlacementPin: Equatable, Sendable {
    var position: NormalizedPoint
    var category: POICategory
}

struct MapFocusRequest: Equatable {
    let id: UUID
    let position: NormalizedPoint

    init(position: NormalizedPoint) {
        self.id = UUID()
        self.position = position
    }
}

struct TiledMapRepresentable: UIViewRepresentable {
    let manifest: MapManifest
    let game: MapGame
    let style: MapStyle
    let pois: [POI]
    let personalPins: [PersonalPin]
    var showPersonalPins: Bool = true
    let communitySpots: [Contribution]
    var myUnpublishedSpots: [Contribution] = []
    var draftPins: [DraftPin] = []
    let poisGeneration: Int
    let spotsGeneration: Int
    let myUnpublishedGeneration: Int
    let personalPinsGeneration: Int
    let foundPOIIDs: Set<String>
    @Binding var viewport: MapViewport
    @Binding var focusRequest: MapFocusRequest?
    /// Non nil pendant qu'on pose une proposition — arme les deux
    /// reconnaisseurs de placement et éteint la frappe du reste du contenu.
    var placement: MapPlacementPin?
    /// Reçoit un point de CONTENU, comme `onLongPress` : la normalisation
    /// appartient à l'appelant, qui a déjà le manifeste sous la main.
    var onPlacementMoved: ((CGPoint) -> Void)?
    let onLongPress: (CGPoint) -> Void
    let onTapPOI: (POI) -> Void
    let onTapPersonalPin: (PersonalPin) -> Void
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

        // Les deux gestes du placement. Ils ne servent que pendant qu'on pose
        // une proposition, et `updateUIView` les éteint le reste du temps.
        //
        // Un TAP déplace l'épingle là où le doigt tombe : c'est lui qui donne la
        // précision, puisqu'on peut zoomer à fond puis viser sans que le pouce
        // couvre la cible. Il ne concurrence rien — un tap et un panoramique ne
        // se disputent jamais un même toucher.
        let placementTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePlacementTap(_:))
        )
        placementTap.delegate = context.coordinator
        placementTap.isEnabled = false
        scrollView.addGestureRecognizer(placementTap)
        context.coordinator.placementTap = placementTap

        // Le GLISSER n'affine que si le toucher démarre sur l'épingle. C'est
        // `gestureRecognizerShouldBegin` qui le décide, et c'est ce qui rend le
        // `require(toFail:)` ci-dessous acceptable sur le geste le plus sensible
        // de l'app : hors de la zone de l'épingle, le reconnaisseur échoue
        // immédiatement, donc le panoramique de la carte ne l'attend pas.
        let placementDrag = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePlacementDrag(_:))
        )
        placementDrag.delegate = context.coordinator
        placementDrag.isEnabled = false
        scrollView.addGestureRecognizer(placementDrag)
        scrollView.panGestureRecognizer.require(toFail: placementDrag)
        context.coordinator.placementDrag = placementDrag

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
        /// Sans elle, une proposition tout juste envoyée n'apparaîtrait qu'au
        /// prochain changement de la carte — c'est-à-dire jamais, sur une carte
        /// encore vide.
        let myUnpublishedGeneration: Int
        let personalPinsGeneration: Int
        /// Éteindre le calque du carnet ne change AUCUNE génération : sans ce
        /// drapeau ici, la puce de filtre ne prendrait effet qu'au prochain
        /// changement de données. Même raison que `canAdopt` plus bas.
        let showPersonalPins: Bool
        let draftPins: [DraftPin]
        /// L'épingle en cours de pose. Dans le jeton parce qu'elle se DESSINE :
        /// sans elle ici, la déplacer d'un tap ne repousserait aucun contenu et
        /// elle resterait clouée à son point de départ. Même raison que
        /// `draftPins`, qui est là pour ça.
        let placement: MapPlacementPin?
        /// Comparé en entier, et c'est le point : marquer un lieu « trouvé » ne
        /// change NI la composition des groupes ni la liste filtrée (sauf sous
        /// « masquer les trouvés »), donc plus rien ne fait avancer la génération
        /// des POI dans ce cas. Sans cet ensemble ici, cocher un lieu ne
        /// repousserait aucun contenu et la coche n'apparaîtrait jamais.
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
            myUnpublishedGeneration: myUnpublishedGeneration,
            personalPinsGeneration: personalPinsGeneration,
            showPersonalPins: showPersonalPins,
            draftPins: draftPins,
            placement: placement,
            foundPOIIDs: foundPOIIDs,
            canAdopt: onAdopt != nil
        )
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Poussé AVANT le garde-fou du jeton, pour la même raison que le
        // recentrage juste en dessous : ce sont les reconnaisseurs qui lisent
        // cette position à chaque toucher, et ils doivent la connaître même
        // quand rien du contenu dessiné n'a bougé.
        context.coordinator.placementContentPoint = placement.map {
            MapGeometry.contentPoint(for: $0.position, manifest: manifest)
        }
        context.coordinator.onPlacementMoved = onPlacementMoved
        context.coordinator.placementTap?.isEnabled = placement != nil
        context.coordinator.placementDrag?.isEnabled = placement != nil

        // Lu AVANT le garde-fou du jeton, et c'est tout le sujet : ce garde-fou
        // retourne dès que rien de la carte n'a changé — ce qui est précisément le
        // cas quand on ne fait que viser une épingle déjà dessinée. Placé après,
        // il l'avalerait, et taper une ligne du carnet ne ferait rien.
        if let focusRequest, context.coordinator.consumedFocus != focusRequest.id {
            context.coordinator.consumedFocus = focusRequest.id
            context.coordinator.focus(on: focusRequest.position, manifest: manifest)
        }
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
            showPersonalPins: showPersonalPins,
            communitySpots: communitySpots,
            myUnpublishedSpots: myUnpublishedSpots,
            draftPins: draftPins,
            placementPin: placement,
            poisGeneration: poisGeneration,
            spotsGeneration: spotsGeneration,
            foundPOIIDs: foundPOIIDs,
            zoom: zoom,
            onTapPOI: onTapPOI,
            onTapPersonalPin: onTapPersonalPin,
            onTapCluster: { [weak coordinator] cluster in
                coordinator?.zoom(to: cluster.position, manifest: manifest)
            },
            onTapCommunityCluster: { [weak coordinator] position in
                coordinator?.zoom(to: position, manifest: manifest)
            },
            onReport: onReport,
            onBlockAuthor: onBlockAuthor,
            onAdopt: onAdopt
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var contentView: UIView?
        weak var scrollView: UIScrollView?
        fileprivate var hostingController: UIHostingController<MapContentSwiftUIView>?
        /// Dernière carte poussée dans la vue — sert à détecter un changement
        /// de carte dans `updateUIView`, qui est appelé pour bien d'autres
        /// raisons (chaque frame de scroll/zoom, notamment).
        fileprivate var displayedGame: MapGame?
        /// Dernier jeton poussé — voir `TiledMapRepresentable.ContentToken`.
        fileprivate var displayedContent: TiledMapRepresentable.ContentToken?
        /// Dernière requête de recentrage honorée. Sans elle, chaque
        /// `updateUIView` — et il y en a beaucoup — rejouerait la même visée.
        fileprivate var consumedFocus: UUID?
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

        /// Recentre sur un point, à une échelle qui ne DÉZOOME jamais.
        ///
        /// Distinct de `zoom(to:)`, qui double le zoom pour délier un groupe : ici
        /// la position est connue et c'est le cadrage qui compte. L'échelle visée
        /// est la plus grande entre le zoom courant et deux fois le minimum. Les
        /// deux bornes comptent, pour des raisons opposées : sans le plancher,
        /// viser depuis le carnet laisserait l'épingle en point de deux pixels au
        /// dézoom de repos ; sans le maximum, taper une ligne ferait RECULER un
        /// joueur qui venait de zoomer sur son quartier.
        func focus(on position: NormalizedPoint, manifest: MapManifest) {
            guard let scrollView, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            let target = min(max(scrollView.zoomScale, scrollView.minimumZoomScale * 2), scrollView.maximumZoomScale)
            let center = MapGeometry.contentPoint(for: position, manifest: manifest)
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

        // MARK: - Placement

        /// Position de l'épingle en pose, en coordonnées de CONTENU. Nil hors
        /// placement, et c'est ce qui désarme les deux reconnaisseurs.
        fileprivate var placementContentPoint: CGPoint?
        fileprivate var onPlacementMoved: ((CGPoint) -> Void)?
        fileprivate weak var placementTap: UITapGestureRecognizer?
        fileprivate weak var placementDrag: UIPanGestureRecognizer?
        /// Point de départ du glisser en cours. Retenu parce que
        /// `translation(in:)` est cumulée depuis le début du geste, pas depuis
        /// la dernière frame.
        private var dragOrigin: CGPoint?

        /// Rayon de préhension de l'épingle, en coordonnées de contenu.
        ///
        /// Le contenu est réduit par la vue de défilement : viser 44 pt d'ÉCRAN
        /// (le minimum du HIG) demande donc un rayon de contenu qui grandit
        /// quand on dézoome. Même raisonnement que `MapRenderState.pinHitCap`.
        private var placementHitRadius: CGFloat {
            22 / max(scrollView?.zoomScale ?? 1, 0.01)
        }

        @objc func handlePlacementTap(_ gesture: UITapGestureRecognizer) {
            guard let contentView else { return }
            onPlacementMoved?(gesture.location(in: contentView))
        }

        @objc func handlePlacementDrag(_ gesture: UIPanGestureRecognizer) {
            guard let contentView else { return }
            switch gesture.state {
            case .began:
                dragOrigin = placementContentPoint
            case .changed, .ended:
                guard let origin = dragOrigin else { return }
                // `translation(in: contentView)` est déjà exprimée dans l'espace
                // du contenu, donc déjà divisée par le zoom : l'épingle suit le
                // doigt à toutes les échelles sans conversion de notre part.
                let translation = gesture.translation(in: contentView)
                onPlacementMoved?(CGPoint(x: origin.x + translation.x, y: origin.y + translation.y))
                if gesture.state == .ended { dragOrigin = nil }
            case .cancelled, .failed:
                dragOrigin = nil
            default:
                break
            }
        }

        /// Le tap déplace où qu'il tombe ; le glisser ne démarre que sur
        /// l'épingle.
        ///
        /// Le `false` du glisser n'est pas qu'un refus : c'est lui qui fait
        /// échouer le reconnaisseur SANS DÉLAI, donc qui empêche le
        /// `require(toFail:)` de retarder le panoramique de la carte.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let point = placementContentPoint else { return false }
            guard gesture === placementDrag else { return true }
            guard let contentView else { return false }
            let location = gesture.location(in: contentView)
            return hypot(location.x - point.x, location.y - point.y) <= placementHitRadius
        }
    }
}
