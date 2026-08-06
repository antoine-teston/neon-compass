import Foundation

/// Le palier d'exploration, calculé sur le NOMBRE de lieux cochés.
///
/// En nombre absolu et pas en pourcentage, délibérément : `ChallengeProgress`
/// peut avoir un `expected` nul quand notre contenu n'énumère pas encore toute
/// une collection, et un pourcentage serait alors faux. C'est déjà pourquoi
/// `ProgressionListView` refuse de tracer un anneau dans ce cas. Un compte
/// reste juste quoi qu'il arrive.
///
/// Rien à voir avec le niveau contributeur (`ContributorGrade`), qui vient de
/// la base : celui-ci est local, il vit hors ligne et sans compte.
enum ExplorerGrade: Int, CaseIterable, Sendable {
    case drifter, scout, pathfinder, cartographer, trailblazer, neonNomad

    /// Calibrés sur les 537 POI du socle `seed-poi.json` : au dernier palier on
    /// a vu l'équivalent de la carte de référence entière.
    var threshold: Int {
        switch self {
        case .drifter: 0
        case .scout: 10
        case .pathfinder: 40
        case .cartographer: 100
        case .trailblazer: 250
        case .neonNomad: 500
        }
    }

    var nameKey: String {
        switch self {
        case .drifter: "profile.explorerGrade.drifter"
        case .scout: "profile.explorerGrade.scout"
        case .pathfinder: "profile.explorerGrade.pathfinder"
        case .cartographer: "profile.explorerGrade.cartographer"
        case .trailblazer: "profile.explorerGrade.trailblazer"
        case .neonNomad: "profile.explorerGrade.neonNomad"
        }
    }

    /// Le repli sur `.drifter` couvre le compte négatif, que `FoundStore` ne
    /// peut pas produire aujourd'hui mais qu'un état corrompu pourrait.
    static func forFound(_ count: Int) -> ExplorerGrade {
        allCases.last { count >= $0.threshold } ?? .drifter
    }

    var next: ExplorerGrade? { ExplorerGrade(rawValue: rawValue + 1) }

    /// Nul au dernier palier : il n'y a plus de suivant, donc plus de barre.
    func progress(found: Int) -> Double? {
        guard let next else { return nil }
        let span = Double(next.threshold - threshold)
        guard span > 0 else { return nil }
        return min(1, max(0, Double(found - threshold) / span))
    }

    func remainingToNext(found: Int) -> Int? {
        guard let next else { return nil }
        return max(0, next.threshold - found)
    }
}
