import Foundation

/// Greedy nearest-neighbor tour over remaining (not-yet-found) collectibles
/// — spec explicitly calls for "tri glouton sur les coordonnées
/// normalisées," not an optimal TSP solve. Starts from the first item in
/// `remaining` (arbitrary but deterministic — callers control ordering by
/// what they pass in) and repeatedly picks the nearest not-yet-visited
/// point by Euclidean distance in normalized [0,1] map coordinates.
enum RoutePlanner {
    static func greedyRoute(from remaining: [POI]) -> [POI] {
        var unvisited = remaining.filter { $0.position != nil }
        guard !unvisited.isEmpty else { return [] }

        var route: [POI] = [unvisited.removeFirst()]
        while !unvisited.isEmpty {
            let current = route.last!.position!
            let nearestIndex = unvisited.indices.min { lhs, rhs in
                distance(current, unvisited[lhs].position!) < distance(current, unvisited[rhs].position!)
            }!
            route.append(unvisited.remove(at: nearestIndex))
        }
        return route
    }

    private static func distance(_ a: NormalizedPoint, _ b: NormalizedPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Le POI le plus proche d'un point, en distance euclidienne sur les
    /// coordonnées normalisées. Sert à convertir le tap qui désigne le départ
    /// de la tournée en un point de la tournée : on ne démarre jamais sur une
    /// coordonnée nue, toujours sur un POI réel.
    ///
    /// Les POI sans position sont ignorés — ils ne sont sur aucune carte.
    static func nearest(to point: NormalizedPoint, in candidates: [POI]) -> POI? {
        candidates
            .filter { $0.position != nil }
            .min { distance(point, $0.position!) < distance(point, $1.position!) }
    }
}
