import Testing
@testable import NeonCompass

struct ProfileHeaderStateTests {
    private func makeProfile(xp: Int, level: Int, rank: Int? = nil) -> Profile {
        Profile(handle: "NEON-FALCON-88", xp: xp, level: level, isPremium: false, rank: rank)
    }

    private func makeState(
        profile: Profile?,
        isLoadingProfile: Bool = false,
        isProEntitled: Bool = false,
        foundCount: Int = 0,
        pendingContributionCount: Int = 0
    ) -> ProfileHeaderState {
        ProfileHeaderState(
            profile: profile,
            isLoadingProfile: isLoadingProfile,
            isProEntitled: isProEntitled,
            foundCount: foundCount,
            pendingContributionCount: pendingContributionCount
        )
    }

    // MARK: - Le correctif

    /// LE test de ce chantier. L'entête affichait « Ton profil » ET
    /// « Niveau 0 / 0 XP » en même temps : le titre suivait
    /// `userID != nil && serverFeatures.isEnabled`, le bloc chiffré suivait un
    /// `if let profile` indépendant. Deux conditions pour une seule question,
    /// réparties entre deux fichiers, donc invisibles au test.
    ///
    /// Il n'y a plus qu'une règle : sans profil, rien de chiffré.
    @Test func nothingNumericWithoutAProfile() {
        for loading in [true, false] {
            let state = makeState(profile: nil, isLoadingProfile: loading, foundCount: 87)
            #expect(state.contributor == nil)
        }
    }

    // MARK: - Le titre

    @Test func titleIsTheHandleWhenTheProfileIsKnown() {
        let state = makeState(profile: makeProfile(xp: 210, level: 2))
        #expect(state.title == .handle("NEON-FALCON-88"))
    }

    /// Sans ce cas, un utilisateur connecté verrait « Ton profil » clignoter le
    /// temps de l'aller-retour réseau avant que son pseudo n'apparaisse.
    @Test func titleIsAPlaceholderWhileLoading() {
        #expect(makeState(profile: nil, isLoadingProfile: true).title == .placeholder)
    }

    @Test func titleIsNeutralWhenThereIsNoProfileAndNoLoad() {
        #expect(makeState(profile: nil, isLoadingProfile: false).title == .neutral)
    }

    // MARK: - La ligne contributeur

    /// L'invitation suit l'XP, PAS le niveau. Les deux ne se recouvrent pas :
    /// le premier palier est à 50 XP, donc on peut avoir contribué une fois
    /// (20 XP) et rester au niveau 0. Lui resservir « propose un lieu »
    /// nierait ce qu'elle vient de faire.
    @Test func zeroXPShowsTheInvitation() {
        let state = makeState(profile: makeProfile(xp: 0, level: 0))
        #expect(state.contributor == .invitation)
    }

    @Test func someXPBelowTheFirstThresholdStillShowsTheXP() {
        let state = makeState(profile: makeProfile(xp: 20, level: 0))
        #expect(state.contributor == .ranked(xp: 20, rank: nil, pending: 0))
    }

    @Test func aRankedContributorCarriesItsXPRankAndPendingCount() {
        let state = makeState(
            profile: makeProfile(xp: 450, level: 3, rank: 342),
            pendingContributionCount: 3
        )
        #expect(state.contributor == .ranked(xp: 450, rank: 342, pending: 3))
    }

    /// Règle existante conservée : pas de rang plutôt qu'un zéro faux.
    @Test func anAbsentRankStaysAbsent() {
        let state = makeState(profile: makeProfile(xp: 450, level: 3, rank: nil))
        #expect(state.contributor == .ranked(xp: 450, rank: nil, pending: 0))
    }

    /// La contribution n'est plus NOMMÉE depuis le 2026-08-19 : deux échelles
    /// nommées dans deux registres étrangers l'un à l'autre, à dix points
    /// d'écart sur la même carte, n'était explicable par rien. Conséquence
    /// heureuse : un palier que la base connaîtrait avant l'app ne fait plus
    /// disparaître de nom, puisqu'il n'y en a plus.
    @Test func aLevelTheAppDoesNotKnowChangesNothing() {
        let state = makeState(profile: makeProfile(xp: 9000, level: 9, rank: 1))
        #expect(state.contributor == .ranked(xp: 9000, rank: 1, pending: 0))
    }

    // MARK: - L'insigne de rang

    /// **L'insigne ne suit PAS la règle « rien de chiffré sans profil », et
    /// c'est délibéré.** Il est calculé sur `foundCount`, qui est local : un
    /// déconnecté a donc son palier dès le premier lieu coché. La règle ne parle
    /// que de l'XP et du rang serveur, les deux seuls nombres qui viennent de la
    /// base.
    @Test func theStreetRankLivesWithoutAProfile() {
        let state = makeState(profile: nil, foundCount: 87)
        #expect(state.streetRank == .getawayDriver)
        #expect(state.foundCount == 87)
        #expect(state.remainingToNext == 13)
        #expect(state.nextRankNameKey == "profile.streetRank.heister")
        #expect(state.rankProgress != nil)
    }

    @Test func theLastRankHasNoBarAndNoNextName() {
        let state = makeState(profile: nil, foundCount: 600)
        #expect(state.streetRank == .kingpin)
        #expect(state.rankProgress == nil)
        #expect(state.remainingToNext == nil)
        #expect(state.nextRankNameKey == nil)
    }

    /// Zéro lieu coché est un vrai départ, pas un vide.
    @Test func zeroFoundIsAStartingRankNotAnEmptyState() {
        let state = makeState(profile: nil, foundCount: 0)
        #expect(state.streetRank == .tourist)
        #expect(state.remainingToNext == 10)
    }

    @Test func proEntitlementPassesThrough() {
        #expect(makeState(profile: nil, isProEntitled: true).isProEntitled)
        #expect(!makeState(profile: nil, isProEntitled: false).isProEntitled)
    }
}
