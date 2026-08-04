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

    @Test func someXPBelowTheFirstThresholdShowsTheXPWithoutAGradeName() {
        let state = makeState(profile: makeProfile(xp: 20, level: 0))
        #expect(state.contributor == .ranked(gradeNameKey: nil, xp: 20, rank: nil, pending: 0))
    }

    @Test func aRankedContributorCarriesItsGradeRankAndPendingCount() {
        let state = makeState(
            profile: makeProfile(xp: 450, level: 3, rank: 342),
            pendingContributionCount: 3
        )
        #expect(state.contributor == .ranked(
            gradeNameKey: "profile.contributorGrade.relay", xp: 450, rank: 342, pending: 3
        ))
    }

    /// Règle existante conservée : pas de rang plutôt qu'un zéro faux.
    @Test func anAbsentRankStaysAbsent() {
        let state = makeState(profile: makeProfile(xp: 450, level: 3, rank: nil))
        #expect(state.contributor == .ranked(
            gradeNameKey: "profile.contributorGrade.relay", xp: 450, rank: nil, pending: 0
        ))
    }

    /// La base peut gagner un palier avant l'app : l'XP et le rang restent
    /// affichés, seul le nom disparaît.
    @Test func anUnknownLevelLosesItsNameButKeepsItsNumbers() {
        let state = makeState(profile: makeProfile(xp: 9000, level: 9, rank: 1))
        #expect(state.contributor == .ranked(gradeNameKey: nil, xp: 9000, rank: 1, pending: 0))
    }

    // MARK: - La jauge d'exploration

    /// Elle est locale : elle vit même sans profil, c'est tout son intérêt.
    @Test func theExplorerGaugeLivesWithoutAProfile() {
        let state = makeState(profile: nil, foundCount: 87)
        #expect(state.explorerGrade == .pathfinder)
        #expect(state.foundCount == 87)
        #expect(state.remainingToNext == 13)
        #expect(state.nextGradeNameKey == "profile.explorerGrade.cartographer")
        #expect(state.explorerProgress != nil)
    }

    @Test func theLastExplorerGradeHasNoBarAndNoNextName() {
        let state = makeState(profile: nil, foundCount: 600)
        #expect(state.explorerGrade == .neonNomad)
        #expect(state.explorerProgress == nil)
        #expect(state.remainingToNext == nil)
        #expect(state.nextGradeNameKey == nil)
    }

    /// Zéro lieu coché est un vrai départ, pas un vide.
    @Test func zeroFoundIsAStartingGradeNotAnEmptyState() {
        let state = makeState(profile: nil, foundCount: 0)
        #expect(state.explorerGrade == .drifter)
        #expect(state.remainingToNext == 10)
    }

    @Test func proEntitlementPassesThrough() {
        #expect(makeState(profile: nil, isProEntitled: true).isProEntitled)
        #expect(!makeState(profile: nil, isProEntitled: false).isProEntitled)
    }
}
