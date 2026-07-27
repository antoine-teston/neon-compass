import CoreGraphics
import Foundation

/// Un groupe de POI agrégés à un niveau de zoom donné. Un cluster d'un seul
/// membre se rend comme un pin normal — c'est le même type des deux côtés pour
/// que la vue n'ait pas à jongler avec deux collections parallèles.
struct POICluster: Identifiable, Equatable, Sendable {
    let id: String
    let position: NormalizedPoint
    let members: [POI]
    /// Catégorie majoritaire du groupe — donne sa couleur à la pastille.
    let dominantCategory: POICategory

    var count: Int { members.count }
    /// Non-nil quand le groupe n'a qu'un membre : la vue rend alors le vrai
    /// pin (icône de catégorie, état « trouvé », tap vers la fiche).
    var single: POI? { members.count == 1 ? members[0] : nil }
}

/// Agrégation des POI en grille, recalculée en fonction du zoom.
///
/// Remplace le décombrement précédent (qui se contentait de MASQUER les pins
/// en surnombre) : on affiche désormais une pastille de comptage, qui se délie
/// en pins individuels au fur et à mesure du zoom. Deux bénéfices distincts —
/// l'information n'est plus perdue (on voit qu'il y a 12 POI là), et le nombre
/// de vues SwiftUI rendues s'effondre, ce qui est le vrai coût quand la carte
/// porte plus de mille points.
enum POIClusterer {
    /// Espacement minimal visé entre deux pastilles, en points écran.
    static let defaultSpacing: CGFloat = 44

    /// Zoom à partir duquel on cesse complètement d'agréger.
    ///
    /// Une grille ne peut pas garantir que tout se délie : la cellule rétrécit
    /// avec le zoom, mais le zoom est plafonné, donc deux POI plus proches que
    /// la cellule au zoom maximal resteraient groupés pour toujours — et le
    /// cas est réel (deux pompes d'une même station, plusieurs passages sous
    /// un même pont). Une pastille qui ne s'ouvre jamais est un cul-de-sac :
    /// passé ce seuil on affiche donc les pins individuellement, quitte à ce
    /// qu'ils se chevauchent. À ce niveau de zoom l'utilisateur a explicitement
    /// demandé le détail, le chevauchement est le moindre mal.
    static let disaggregationZoom: CGFloat = 2

    /// Niveau de zoom quantifié en demi-octaves.
    ///
    /// Sans quantification, la taille des cellules suivrait le zoom en continu
    /// et les groupes se scinderaient/refusionneraient à chaque frame de
    /// pincement — les compteurs clignoteraient et l'identité des vues
    /// changerait sans arrêt. Par paliers, les regroupements sont stables
    /// entre deux seuils.
    static func level(for zoomScale: CGFloat) -> Int {
        guard zoomScale > 0, zoomScale.isFinite else { return 0 }
        return Int((log2(Double(zoomScale)) * 2).rounded())
    }

    static func quantizedScale(forLevel level: Int) -> CGFloat {
        CGFloat(pow(2.0, Double(level) / 2))
    }

    /// - Parameters:
    ///   - contentSize: côté de la carte en coordonnées de contenu (px pleine
    ///     résolution), pour convertir l'espacement écran en taille de cellule.
    static func clusters(
        pois: [POI],
        zoomScale: CGFloat,
        contentSize: CGFloat,
        spacing: CGFloat = defaultSpacing
    ) -> [POICluster] {
        guard contentSize > 0, spacing > 0 else { return [] }

        if zoomScale >= disaggregationZoom {
            return pois.compactMap { poi in
                guard let position = poi.position else { return nil }
                return POICluster(id: poi.id, position: position, members: [poi],
                                  dominantCategory: poi.category)
            }
        }

        let scale = quantizedScale(forLevel: level(for: zoomScale))
        guard scale > 0, scale.isFinite else { return [] }
        let cell = Double(spacing / scale)
        guard cell > 0, cell.isFinite else { return [] }

        var buckets: [Int64: [POI]] = [:]
        buckets.reserveCapacity(pois.count)
        for poi in pois {
            guard let position = poi.position else { continue }
            let column = Int64((position.x * Double(contentSize)) / cell)
            let row = Int64((position.y * Double(contentSize)) / cell)
            // Clé entière plutôt qu'une paire : reste en O(n) sans allocation
            // par point.
            buckets[row &* 1_000_003 &+ column, default: []].append(poi)
        }

        // Tri par id : l'ordre d'itération d'un Dictionary n'est pas garanti
        // stable, et un ForEach dont l'ordre change à chaque recalcul ferait
        // recréer toutes les vues.
        return buckets
            .map { key, members in
                POICluster(
                    id: "c\(key)",
                    position: centroid(of: members),
                    members: members,
                    dominantCategory: dominantCategory(of: members)
                )
            }
            .sorted { $0.id < $1.id }
    }

    private static func centroid(of members: [POI]) -> NormalizedPoint {
        var x = 0.0, y = 0.0, n = 0.0
        for member in members {
            guard let position = member.position else { continue }
            x += position.x
            y += position.y
            n += 1
        }
        guard n > 0 else { return NormalizedPoint(x: 0, y: 0) }
        return NormalizedPoint(x: x / n, y: y / n)
    }

    /// Catégorie la plus représentée. Égalité tranchée par l'ordre de
    /// déclaration de `POICategory`, pour que la couleur d'une pastille ne
    /// dépende pas de l'ordre d'arrivée des POI.
    private static func dominantCategory(of members: [POI]) -> POICategory {
        var counts: [POICategory: Int] = [:]
        for member in members { counts[member.category, default: 0] += 1 }
        return POICategory.allCases.max { lhs, rhs in
            (counts[lhs] ?? 0, POICategory.allCases.firstIndex(of: rhs) ?? 0)
                < (counts[rhs] ?? 0, POICategory.allCases.firstIndex(of: lhs) ?? 0)
        } ?? .landmark
    }
}
