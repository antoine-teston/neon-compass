import Testing
@testable import NeonCompass

struct ContributorGradeTests {
    @Test func eachLevelHasItsGrade() {
        #expect(ContributorGrade.named(level: 1) == .spotter)
        #expect(ContributorGrade.named(level: 2) == .beacon)
        #expect(ContributorGrade.named(level: 3) == .relay)
        #expect(ContributorGrade.named(level: 4) == .lighthouse)
        #expect(ContributorGrade.named(level: 5) == .gridKeeper)
    }

    /// Le niveau 0 n'est pas un grade : c'est l'absence de grade. L'entête
    /// affiche alors l'XP sans nom, ou l'invitation si l'XP est à zéro.
    @Test func levelZeroHasNoGrade() {
        #expect(ContributorGrade.named(level: 0) == nil)
    }

    /// La base peut gagner un palier avant que l'app le connaisse : un niveau
    /// inconnu ne doit pas planter, il doit simplement n'avoir aucun nom.
    @Test func levelsOutsideTheKnownRangeHaveNoGrade() {
        #expect(ContributorGrade.named(level: 6) == nil)
        #expect(ContributorGrade.named(level: 99) == nil)
        #expect(ContributorGrade.named(level: -1) == nil)
    }

    @Test func nameKeysAreDistinctAndPrefixed() {
        let keys = ContributorGrade.allCases.map(\.nameKey)
        #expect(Set(keys).count == ContributorGrade.allCases.count)
        #expect(keys.allSatisfy { $0.hasPrefix("profile.contributorGrade.") })
    }

    /// Aucun seuil XP côté client : la colonne générée de `profiles` est seule
    /// à les détenir. Ce test fige l'intention — si quelqu'un ajoute un
    /// `threshold`, il saura qu'il rouvre une duplication supprimée exprès.
    @Test func gradesCarryNoXPThreshold() {
        #expect(ContributorGrade.allCases.count == 5)
        #expect(ContributorGrade.spotter.rawValue == 1)
    }
}
