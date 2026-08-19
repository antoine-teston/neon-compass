import Foundation

/// Tout l'état de la carte Identité, dérivé sans SwiftUI et donc testable.
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
///
/// **L'insigne de rang, lui, ne suit pas cette règle et n'a pas à la suivre :**
/// il est calculé sur `foundCount`, qui est local. Un déconnecté a donc son
/// palier dès le premier lieu coché. La règle ne parle que de l'XP et du rang
/// serveur, les deux seuls nombres qui viennent de la base.
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
        /// Des chiffres, jamais un nom : la dénomination de contribution a été
        /// retirée le 2026-08-19. Deux échelles nommées dans deux registres
        /// étrangers l'un à l'autre, à dix points d'écart sur la même carte,
        /// n'était explicable par rien.
        case ranked(xp: Int, rank: Int?, pending: Int)
    }

    let title: Title
    let isProEntitled: Bool
    let streetRank: StreetRank
    let foundCount: Int
    let rankProgress: Double?
    let remainingToNext: Int?
    let nextRankNameKey: String?
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
                : .ranked(xp: profile.xp, rank: profile.rank, pending: pendingContributionCount)
        } else {
            title = isLoadingProfile ? .placeholder : .neutral
            contributor = nil
        }

        self.isProEntitled = isProEntitled
        self.foundCount = foundCount
        let rank = StreetRank.forFound(foundCount)
        streetRank = rank
        rankProgress = rank.progress(found: foundCount)
        remainingToNext = rank.remainingToNext(found: foundCount)
        nextRankNameKey = rank.next?.nameKey
    }
}
