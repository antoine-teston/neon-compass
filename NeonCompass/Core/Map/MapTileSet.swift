import CoreGraphics

/// Une tuile, désignée par son niveau et sa position dans la grille de ce
/// niveau. Le niveau fait partie de la clé : deux tuiles de niveaux différents
/// couvrent la même région sans être interchangeables.
struct MapTileKey: Hashable, Sendable {
    let level: Int
    let x: Int
    let y: Int
}

/// Quel niveau pour quelle échelle, quelles tuiles pour quelle fenêtre.
///
/// Tout est ici et rien n'est ailleurs : `MapTileLayerView` ne fait que poser
/// ce que ces fonctions décident. C'est ce partage qui rend le pavage testable
/// — le comportement d'un `CATiledLayer` ne se serait vérifié qu'à l'œil.
enum MapTileSet {
    /// Combien de pixels de l'image l'écran peut montrer.
    static func displayablePixels(zoomScale: CGFloat, contentSize: CGFloat, displayScale: CGFloat) -> CGFloat {
        contentSize * max(zoomScale, 0) * max(displayScale, 1)
    }

    /// Le niveau à charger, ou nil quand le socle suffit.
    ///
    /// Nil sous `manifest.base` est la décision qui tient l'empreinte mémoire.
    /// Au repos toute la carte est visible : engager un niveau y ferait charger
    /// ses 256 tuiles, soit 256 Mo — plus cher que l'image unique qu'on
    /// remplace. Le socle a déjà 4 096 px, l'écran n'en montre que ≈2 642.
    ///
    /// Aucune constante de tolérance ici, et c'est délibéré : l'ancien
    /// `maxUpscale` de 1,5 était un jugement, celui-ci est de la géométrie.
    static func level(for displayable: CGFloat, manifest: MapTileManifest) -> Int? {
        guard displayable > CGFloat(manifest.base) else { return nil }
        for level in manifest.levels where CGFloat(level.side) >= displayable { return level.side }
        // Au-delà du plus fin on agrandit. Retomber sur le socle au zoom
        // maximal serait exactement l'inverse du but poursuivi.
        return manifest.levels.last?.side
    }

    /// Les tuiles couvrant le rectangle visible, plus une marge.
    ///
    /// La marge n'est pas du confort : un panoramique découvre la tuile
    /// suivante avant que son décodage n'aboutisse, et sans elle on verrait le
    /// socle agrandi défiler devant le doigt.
    static func tiles(
        level: Int,
        visibleContentRect: CGRect,
        contentSize: CGFloat,
        manifest: MapTileManifest,
        margin: Int = 1
    ) -> [MapTileKey] {
        guard let descriptor = manifest.levels.first(where: { $0.side == level }), descriptor.count > 0 else { return [] }
        let step = contentSize / CGFloat(descriptor.count)
        guard step > 0 else { return [] }
        let last = descriptor.count - 1
        let x0 = Int(floor(visibleContentRect.minX / step)) - margin
        let x1 = Int(floor((visibleContentRect.maxX - 0.001) / step)) + margin
        let y0 = Int(floor(visibleContentRect.minY / step)) - margin
        let y1 = Int(floor((visibleContentRect.maxY - 0.001) / step)) + margin
        // `x0 <= x1, y0 <= y1` : pas un bornage de plus, c'est le cas où la fenêtre demandée est vide et où l'ordre des bornes s'inverse.
        guard x1 >= 0, y1 >= 0, x0 <= last, y0 <= last, x0 <= x1, y0 <= y1 else { return [] }
        var keys: [MapTileKey] = []
        for y in max(0, y0)...min(last, y1) {
            for x in max(0, x0)...min(last, x1) {
                keys.append(MapTileKey(level: level, x: x, y: y))
            }
        }
        return keys
    }

    /// Où poser la tuile dans l'espace de contenu, en points.
    static func frame(for key: MapTileKey, contentSize: CGFloat, manifest: MapTileManifest) -> CGRect {
        guard let descriptor = manifest.levels.first(where: { $0.side == key.level }), descriptor.count > 0 else { return .zero }
        let step = contentSize / CGFloat(descriptor.count)
        return CGRect(x: CGFloat(key.x) * step, y: CGFloat(key.y) * step, width: step, height: step)
    }

    /// Agrandissement toléré au-delà du niveau le plus fin.
    ///
    /// 1,10 n'est pas un arbitrage neuf : c'est exactement ce que le plafond
    /// de 3,3 réclamait déjà sur un appareil ×3 — 2 048 pt × 3,3 × 3 font
    /// 20 275 px demandés aux 18 432 du niveau le plus fin. La constante ne
    /// fait que nommer ce qu'on faisait.
    static let pyramidUpscale: CGFloat = 1.10

    /// Sans pyramide, on tolère 3,75× — là encore ce que le plafond de 2,5
    /// réclamait déjà sur ×3 : 2 048 × 2,5 × 3 font 15 360 px demandés aux
    /// 4 096 du socle. Bien plus permissif que 1,10, et ce n'est pas une
    /// inconséquence : la carte de référence n'a rien de plus fin à montrer,
    /// donc son plafond arbitre entre « on voit du flou » et « on ne peut plus
    /// s'approcher du tout », pas entre deux niveaux de netteté.
    static let baseUpscale: CGFloat = 3.75

    /// Côté du socle quand aucun manifeste ne le déclare, en pixels.
    ///
    /// Une carte sans pyramide n'a pas de manifeste, donc pas d'endroit où
    /// lire ce nombre. Ce n'est pas une convention pour autant :
    /// `MapArtResourcesTests.everyBaseImageIsShippedAtFourThousandNinetySix`
    /// l'épingle sur les vrais fichiers, tous les quatre.
    static let unpyramidedBaseSide: CGFloat = 4096

    /// Le plafond de zoom, en géométrie plutôt qu'en constante.
    ///
    /// Le contenu fait `contentSize` points pour un certain nombre de pixels
    /// d'image, et un écran en rend `zoom × displayScale` par point. Le zoom
    /// au-delà duquel on agrandirait plus que la tolérance est donc :
    ///
    ///     plafond = côtéSource × tolérance ÷ (contentSize × displayScale)
    ///
    /// Un appareil ×2 y gagne une fois et demie le plafond d'un ×3, pour la
    /// MÊME finesse à l'écran. C'est le défaut que ce calcul corrige : à
    /// plafond constant, l'iPad n'affichait que 73 % de la finesse linéaire
    /// qu'il embarque.
    ///
    /// Le plancher de 1 n'est pas décoratif : `UIScrollView` accepte sans
    /// broncher un `maximumZoomScale` sous son `minimumZoomScale`, et le
    /// résultat est une carte qu'on ne peut plus manipuler du tout.
    static func maximumZoomScale(
        contentSize: CGFloat,
        manifest: MapTileManifest?,
        displayScale: CGFloat
    ) -> CGFloat {
        guard contentSize > 0 else { return 1 }
        let sourceSide: CGFloat
        let tolerance: CGFloat
        if let finest = manifest?.levels.last?.side, finest > 0 {
            sourceSide = CGFloat(finest)
            tolerance = pyramidUpscale
        } else {
            sourceSide = unpyramidedBaseSide
            tolerance = baseUpscale
        }
        return max(sourceSide * tolerance / (contentSize * max(displayScale, 1)), 1)
    }
}
