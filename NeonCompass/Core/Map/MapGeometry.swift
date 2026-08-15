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

/// Portion de carte pour laquelle on construit réellement des pastilles.
///
/// Le contenu zoomable couvre la carte ENTIÈRE, à toutes les échelles : au zoom
/// maximal, 5 % de sa surface est à l'écran, et les 95 % restants étaient tout
/// de même bâtis en vues SwiftUI. Or le coût mesuré est linéaire en nombre de
/// pastilles (~0,066 ms l'unité, contre 12 ms de plancher fixe par frame) : à
/// 537 points désagrégés, c'est 35 ms par frame pour une trentaine de pastilles
/// effectivement visibles.
///
/// La fenêtre est QUANTIFIÉE et débordante d'une marge. Les deux propriétés
/// comptent, pour des raisons opposées :
///
/// - sans quantification, la fenêtre changerait à chaque frame de panoramique
///   et ferait réévaluer le contenu en continu — le panoramique, sinon gratuit,
///   deviendrait le chemin le plus cher ;
/// - sans marge, une pastille apparaîtrait pile au bord de l'écran au moment
///   où elle y entre, ce qui se voit.
struct MapRenderWindow: Equatable, Sendable {
    /// Côté d'une tuile de quantification, en points d'ÉCRAN.
    ///
    /// En points d'écran, et non en pixels de contenu : c'est tout le sujet.
    /// Une tuile de taille fixe dans le CONTENU vaut, à l'écran, une distance
    /// qui varie avec le zoom — 27 pt au dézoom maximal contre 160 pt au zoom
    /// maximal, sur iPhone. Panoramiquer d'une même distance visible franchissait
    /// donc six fois plus de tuiles une fois dézoomé, et chaque franchissement
    /// reconstruit toutes les pastilles.
    ///
    /// Mesuré, panoramique scripté de 300 images à zoom constant : 131
    /// reconstructions au dézoom maximal contre 45 au zoom maximal, pour 129
    /// pastilles contre 79. D'où 58,6 fps d'un côté et 59,4 de l'autre — et
    /// 60,0 dès qu'on retirait les pastilles, l'illustration restant affichée.
    ///
    /// Exprimée à l'écran, la cadence de franchissement devient la même partout.
    /// Effet de bord voulu : au dézoom maximal les tuiles deviennent si larges
    /// dans le contenu que la fenêtre dépasse le seuil de repli et se ramène à
    /// la carte entière — donc plus aucune reconstruction pendant un panoramique,
    /// exactement là où le découpage ne rapportait presque rien.
    static let tileScreenSize: CGFloat = 96
    /// Marge, en tuiles, ajoutée de chaque côté — l'ordre de grandeur d'une
    /// pastille suffit, la fenêtre étant recalculée sur la frame même où on
    /// franchit une tuile.
    static let marginTiles: Double = 1

    /// Au-delà de cette part de la carte couverte, la fenêtre est ramenée à
    /// `whole`. Ce n'est pas une approximation, c'est le point d'équilibre :
    ///
    /// une fenêtre découpée dépend du panoramique, donc elle change — et chaque
    /// changement est une réévaluation du contenu. Mesuré au dézoom maximal sur
    /// iPad, où presque toute la carte est visible : le découpage retranchait
    /// UNE pastille sur 204 et faisait passer les réévaluations de 6 à 26 sur
    /// 240 frames, soit 56,3 → 53,8 fps. Il se payait sans rien rapporter.
    ///
    /// En dessous du seuil il rapporte largement : au zoom maximal, 531
    /// pastilles tombent à 237, et 19,0 → 36,0 fps.
    static let coverageSnappingToWhole = 0.6

    /// Bornes normalisées [0, 1], déjà arrondies vers l'extérieur sur la grille.
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    /// Toute la carte. C'est le repli SÛR : une géométrie inconnue doit tout
    /// afficher, jamais rien — une pastille manquante est un défaut visible,
    /// une pastille en trop ne coûte que du temps.
    static let whole = MapRenderWindow(unchecked: 0, 0, 1, 1)

    private init(unchecked minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// - Parameters:
    ///   - visibleContentRect: fenêtre visible en coordonnées de contenu pleine
    ///     résolution (donc déjà divisée par le zoom).
    ///   - zoomScale: nécessaire parce que la quantification se mesure à
    ///     l'écran, pas dans le contenu.
    init(visibleContentRect rect: CGRect, contentSize: CGFloat, zoomScale: CGFloat) {
        guard contentSize > 0, zoomScale > 0, zoomScale.isFinite,
              rect.width > 0, rect.height > 0,
              rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite else {
            self = .whole
            return
        }
        let tile = Double(Self.tileScreenSize / zoomScale)
        let size = Double(contentSize)
        guard tile > 0, tile.isFinite else {
            self = .whole
            return
        }
        func lower(_ value: CGFloat) -> Double {
            ((Double(value) / tile).rounded(.down) - Self.marginTiles) * tile / size
        }
        func upper(_ value: CGFloat) -> Double {
            ((Double(value) / tile).rounded(.up) + Self.marginTiles) * tile / size
        }
        self.init(
            minX: lower(rect.minX), minY: lower(rect.minY),
            maxX: upper(rect.maxX), maxY: upper(rect.maxY)
        )
    }

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let clampedMinX = min(max(minX, 0), 1)
        let clampedMinY = min(max(minY, 0), 1)
        let clampedMaxX = min(max(maxX, clampedMinX), 1)
        let clampedMaxY = min(max(maxY, clampedMinY), 1)

        let coverage = (clampedMaxX - clampedMinX) * (clampedMaxY - clampedMinY)
        if coverage >= Self.coverageSnappingToWhole {
            self = .whole
            return
        }
        self.init(unchecked: clampedMinX, clampedMinY, clampedMaxX, clampedMaxY)
    }

    func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

/// Ce qu'il faut poser sur le calque de fondu pour l'état courant.
///
/// Deux nombres, et pas un de plus : le calque ne change ni de cadre ni
/// d'image quand on zoome, ce qui est tout l'intérêt du procédé.
struct MapEdgeFade: Equatable, Sendable {
    /// `contentsScale` du calque.
    ///
    /// Le calque vit dans l'espace de CONTENU, que le zoom agrandit. Porter
    /// son échelle à `displayScale × zoom` fait qu'un pixel de l'image vaut un
    /// pixel de l'appareil : la bande gravée mesure alors le même nombre de
    /// points d'ÉCRAN à tous les zooms, sans qu'on regrave ni redimensionne
    /// quoi que ce soit.
    let contentsScale: CGFloat

    /// Le fondu entre en scène à mesure que le bord quitte l'écran.
    ///
    /// Au repos la carte affleure exactement deux des quatre bords — c'est la
    /// définition de l'échelle de repos, qui couvre l'écran sans bande vide.
    /// Un fondu toujours actif y poserait donc une vignette de 80 pt en haut
    /// et en bas, alors qu'au repos il n'y a aucun bord à masquer.
    let opacity: Float
}

enum MapGeometry {
    static func fullSize(for manifest: MapManifest) -> CGFloat {
        CGFloat(manifest.size)
    }

    /// Fenêtre visible en coordonnées de contenu, à partir de l'état d'une vue
    /// de défilement. `contentOffset` peut être négatif quand les encarts de
    /// centrage laissent du vide autour de la carte — la fenêtre déborde alors
    /// du contenu, ce que `MapRenderWindow` borne.
    static func visibleContentRect(bounds: CGSize, contentOffset: CGPoint, zoomScale: CGFloat) -> CGRect {
        let scale = max(zoomScale, 0.0001)
        return CGRect(
            x: contentOffset.x / scale,
            y: contentOffset.y / scale,
            width: bounds.width / scale,
            height: bounds.height / scale
        )
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
    /// by `zoomScale` within `bounds`. Below the resting scale
    /// (`coverZoomScale`), this is the natural letterbox margin — clamped to
    /// zero on any axis where the scaled content already fills or exceeds it
    /// (never negative). Beyond the resting scale, every axis instead floors
    /// to `bounds/2` — see the overscroll comment below.
    static func centeringInsets(contentSize: CGSize, zoomScale: CGFloat, in bounds: CGSize) -> ContentInsets {
        let scaledWidth = contentSize.width * zoomScale
        let scaledHeight = contentSize.height * zoomScale
        // Plancher de débord, actif seulement au-delà de l'échelle de repos
        // (coverZoomScale) : en-deçà, le centrage naturel doit rester
        // inchangé (0 quand le contenu remplit déjà l'axe), sinon la carte
        // s'ouvrirait au lancement avec une marge géante de chaque côté — la
        // carte remplit pourtant l'écran au repos par construction (le
        // plancher de zoom EST coverZoomScale). Au-delà du repos, sans
        // plancher l'inset retombe à 0 dès qu'un axe dépasse la vue, le
        // défilement bute sur le bord de l'image, et une épingle côtière ne
        // peut jamais être amenée au centre — la précision du geste de
        // soumission en dépend.
        let overscrolling = zoomScale > coverZoomScale(contentSize: contentSize, in: bounds)
        let horizontal = max((bounds.width - scaledWidth) / 2, overscrolling ? bounds.width / 2 : 0)
        let vertical = max((bounds.height - scaledHeight) / 2, overscrolling ? bounds.height / 2 : 0)
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

    /// L'état du calque de fondu, pour une position, un zoom et un appareil
    /// donnés.
    ///
    /// - Parameter band: l'épaisseur voulue, en points d'ÉCRAN.
    /// - Parameter visibleContentRect: ce que la fenêtre montre, en
    ///   coordonnées de CONTENU — celui que rend `visibleContentRect(bounds:
    ///   contentOffset:zoomScale:)`, non borné aux limites de la carte, donc
    ///   négatif ou débordant dès qu'on voit du fond.
    ///
    /// L'opacité se règle sur le FOND visible à côté de la carte, et non sur
    /// la taille de celle-ci. C'est la seule mesure qui distingue les deux
    /// situations que le zoom seul confond : une carte à peine plus grande que
    /// l'écran et centrée (aucun bord visible, donc aucune coupe à cacher, et
    /// un fondu y poserait une vignette), et la même carte dont on a tiré un
    /// bord au milieu de l'écran (une arête franche à cacher). Les encarts de
    /// débord valant une demi-fenêtre au-delà du repos, le second cas est
    /// atteignable dès le premier point de zoom au-dessus du repos.
    ///
    /// Le maximum sur les quatre côtés, et non le minimum : un seul calque
    /// sert les quatre, donc c'est le côté le plus découvert qui commande.
    static func edgeFade(
        band: CGFloat,
        contentSize: CGSize,
        visibleContentRect: CGRect,
        zoomScale: CGFloat,
        displayScale: CGFloat
    ) -> MapEdgeFade {
        let zoom = max(zoomScale, 0.0001)
        let exposure = max(
            max(-visibleContentRect.minX, visibleContentRect.maxX - contentSize.width),
            max(-visibleContentRect.minY, visibleContentRect.maxY - contentSize.height)
        ) * zoom
        let ramp = band > 0 ? min(max(exposure / band, 0), 1) : 0
        return MapEdgeFade(
            contentsScale: max(displayScale, 1) * zoom,
            opacity: Float(ramp)
        )
    }
}
