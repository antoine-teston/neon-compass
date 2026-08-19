import Foundation

/// Le palier d'exploration, calculé sur le NOMBRE de lieux cochés.
///
/// En nombre absolu et pas en pourcentage, délibérément : `ChallengeProgress`
/// peut avoir un `expected` nul quand notre contenu n'énumère pas encore toute
/// une collection, et un pourcentage serait alors faux. C'est déjà pourquoi la
/// Découverte refuse de tracer un arc dans ce cas. Un compte reste juste quoi
/// qu'il arrive.
///
/// **C'est la seule échelle nommée de l'app.** Il y en avait deux jusqu'au
/// 2026-08-19 — celle-ci et `ContributorGrade`, dans deux registres étrangers
/// l'un à l'autre, à dix points d'écart sur la même carte. La contribution ne
/// porte plus que des chiffres.
///
/// Le registre est une ascension dans le milieu, et il a été choisi en écrivant
/// trois échelles complètes dans les cinq langues avant de trancher : c'est le
/// passage en ES/IT/DE qui a éliminé les deux autres, l'une donnant deux
/// quasi-synonymes indistinguables (`Explorador`/`Localizador`,
/// `Kundschafter`/`Späher`), l'autre un palier terne et des libellés de 18
/// caractères en capitales.
///
/// Aucun de ces six noms ne vient de la fiction Rockstar, et aucun n'est une
/// marque : c'est de la prose que nous écrivons, donc l'exception nominative
/// des champs de contenu ne s'y applique pas.
enum StreetRank: Int, CaseIterable, Sendable {
    case tourist, runner, getawayDriver, heister, lieutenant, kingpin

    /// Calibrés sur les 537 POI du socle `seed-poi.json` : au dernier palier on
    /// a vu l'équivalent de la carte de référence entière. Inchangés depuis
    /// `ExplorerGrade`, dont ce type reprend l'échelle — seul le vocabulaire a
    /// changé, et rien ne justifiait de rouvrir un calibrage au passage.
    var threshold: Int {
        switch self {
        case .tourist: 0
        case .runner: 10
        case .getawayDriver: 40
        case .heister: 100
        case .lieutenant: 250
        case .kingpin: 500
        }
    }

    var nameKey: String {
        switch self {
        case .tourist: "profile.streetRank.tourist"
        case .runner: "profile.streetRank.runner"
        case .getawayDriver: "profile.streetRank.getawayDriver"
        case .heister: "profile.streetRank.heister"
        case .lieutenant: "profile.streetRank.lieutenant"
        case .kingpin: "profile.streetRank.kingpin"
        }
    }

    /// Le glyphe de l'insigne. Il n'a pas à être parlant tout seul — le nom du
    /// palier est à côté de lui — mais il doit monter avec le rang, sinon
    /// l'insigne ne dit rien de plus que le texte qu'il accompagne.
    var symbolName: String {
        switch self {
        case .tourist: "figure.walk"
        case .runner: "figure.run"
        case .getawayDriver: "car.fill"
        case .heister: "bag.fill"
        case .lieutenant: "star.fill"
        case .kingpin: "crown.fill"
        }
    }

    /// Le repli sur `.tourist` couvre le compte négatif, que `FoundStore` ne
    /// peut pas produire aujourd'hui mais qu'un état corrompu pourrait.
    static func forFound(_ count: Int) -> StreetRank {
        allCases.last { count >= $0.threshold } ?? .tourist
    }

    var next: StreetRank? { StreetRank(rawValue: rawValue + 1) }

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
