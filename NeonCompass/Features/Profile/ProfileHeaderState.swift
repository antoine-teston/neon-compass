import Foundation

/// Tout l'état de l'entête du Profil, dérivé sans SwiftUI et donc testable.
///
/// Ce type existe pour une raison précise. L'entête affichait « Ton profil » —
/// le titre anonyme — ET « Niveau 0 / 0 XP » dans le même bloc : le titre
/// suivait `userID != nil && serverFeatures.isEnabled` dans `ProfileScreen`,
/// le bloc chiffré suivait un `if let profile` dans `ProfileHeaderView`. Deux
/// conditions pour une seule question, réparties entre deux fichiers, donc
/// aucun test ne pouvait voir la combinaison qui les contredit.
///
/// Il n'y a plus qu'une règle : **tout ce qui est chiffré suit `profile != nil`,
/// et rien d'autre.** L'entête ne reçoit délibérément PAS de `isSignedIn` — le
/// profil n'est chargé que connecté, donc `contributor != nil` implique déjà
/// « connecté », et les états « déconnecté » et « serveur coupé » rendent
/// volontairement la même chose.
struct ProfileHeaderState: Equatable {
    enum Title: Equatable {
        case handle(String)
        /// Chargement en cours. Rendu en gabarit `.redacted` : sans ce cas, un
        /// connecté verrait « Ton profil » clignoter avant son pseudo.
        case placeholder
        case neutral
    }

    enum Contributor: Equatable {
        /// XP à zéro. Le seul endroit de l'app qui dise comment l'XP se gagne.
        case invitation
        /// `gradeNameKey` est nul sous 50 XP (niveau 0), et pour tout niveau
        /// que l'app ne connaît pas encore.
        case ranked(gradeNameKey: String?, xp: Int, rank: Int?, pending: Int)
    }

    let title: Title
    let isProEntitled: Bool
    let explorerGrade: ExplorerGrade
    let foundCount: Int
    let explorerProgress: Double?
    let remainingToNext: Int?
    let nextGradeNameKey: String?
    let contributor: Contributor?

    init(
        profile: Profile?,
        isLoadingProfile: Bool,
        isProEntitled: Bool,
        foundCount: Int,
        pendingContributionCount: Int
    ) {
        if let profile {
            title = .handle(profile.handle)
            // Sur l'XP et non sur le niveau : le premier palier étant à 50, on
            // peut avoir contribué une fois et rester au niveau 0.
            contributor = profile.xp == 0
                ? .invitation
                : .ranked(
                    gradeNameKey: ContributorGrade.named(level: profile.level)?.nameKey,
                    xp: profile.xp,
                    rank: profile.rank,
                    pending: pendingContributionCount
                )
        } else {
            title = isLoadingProfile ? .placeholder : .neutral
            contributor = nil
        }

        self.isProEntitled = isProEntitled
        self.foundCount = foundCount
        let grade = ExplorerGrade.forFound(foundCount)
        explorerGrade = grade
        explorerProgress = grade.progress(found: foundCount)
        remainingToNext = grade.remainingToNext(found: foundCount)
        nextGradeNameKey = grade.next?.nameKey
    }
}
