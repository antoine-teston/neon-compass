import Foundation

/// Nomme un `Profile.level` reçu de la base. Rien de plus.
///
/// Aucun seuil XP n'est déclaré ici, et c'est délibéré : `profiles.level` est
/// une colonne GÉNÉRÉE (`20260802120000_initial_schema.sql:24-33`), et la
/// migration qui l'a introduite dit pourquoi — « il n'y a plus qu'un seul
/// endroit où écrire l'XP, et zéro endroit où recalculer le niveau ». Déclarer
/// les seuils ici rouvrirait exactement la duplication qu'elle a fermée.
///
/// Conséquence assumée : pas de barre de progression côté contributeur. Une
/// ligne de texte suffit, et elle ne peut pas dériver de la base.
enum ContributorGrade: Int, CaseIterable, Sendable {
    case spotter = 1, beacon, relay, lighthouse, gridKeeper

    var nameKey: String {
        switch self {
        case .spotter: "profile.contributorGrade.spotter"
        case .beacon: "profile.contributorGrade.beacon"
        case .relay: "profile.contributorGrade.relay"
        case .lighthouse: "profile.contributorGrade.lighthouse"
        case .gridKeeper: "profile.contributorGrade.gridKeeper"
        }
    }

    /// Nul au niveau 0 — l'absence de grade, pas un grade — et nul aussi pour
    /// tout entier hors 1…5 : la base peut gagner un palier avant l'app.
    static func named(level: Int) -> ContributorGrade? {
        ContributorGrade(rawValue: level)
    }
}
