import Testing
@testable import NeonCompass

struct ExplorerGradeTests {
    /// Les bornes, pas le milieu : c'est là que les erreurs de comparaison
    /// vivent. 9 est encore Vagabond, 10 est déjà Repéreur.
    @Test func thresholdsAreExact() {
        #expect(ExplorerGrade.forFound(0) == .drifter)
        #expect(ExplorerGrade.forFound(9) == .drifter)
        #expect(ExplorerGrade.forFound(10) == .scout)
        #expect(ExplorerGrade.forFound(39) == .scout)
        #expect(ExplorerGrade.forFound(40) == .pathfinder)
        #expect(ExplorerGrade.forFound(99) == .pathfinder)
        #expect(ExplorerGrade.forFound(100) == .cartographer)
        #expect(ExplorerGrade.forFound(249) == .cartographer)
        #expect(ExplorerGrade.forFound(250) == .trailblazer)
        #expect(ExplorerGrade.forFound(499) == .trailblazer)
        #expect(ExplorerGrade.forFound(500) == .neonNomad)
        #expect(ExplorerGrade.forFound(10_000) == .neonNomad)
    }

    /// `FoundStore` ne peut pas rendre un compte négatif, mais un état
    /// corrompu ne doit pas faire tomber l'entête.
    @Test func negativeCountFallsBackToFirstGrade() {
        #expect(ExplorerGrade.forFound(-1) == .drifter)
    }

    @Test func lastGradeHasNoNext() {
        #expect(ExplorerGrade.neonNomad.next == nil)
        #expect(ExplorerGrade.neonNomad.progress(found: 600) == nil)
        #expect(ExplorerGrade.neonNomad.remainingToNext(found: 600) == nil)
    }

    @Test func nextIsTheFollowingGrade() {
        #expect(ExplorerGrade.drifter.next == .scout)
        #expect(ExplorerGrade.trailblazer.next == .neonNomad)
    }

    /// 87 lieux : Éclaireur (40), le suivant est Cartographe (100).
    /// Il reste 13, et on a fait 47/60 du chemin.
    @Test func progressAndRemainingWithinAGrade() throws {
        let grade = ExplorerGrade.forFound(87)
        #expect(grade == .pathfinder)
        #expect(grade.remainingToNext(found: 87) == 13)
        let progress = try #require(grade.progress(found: 87))
        #expect(abs(progress - (47.0 / 60.0)) < 0.0001)
    }

    /// Pile sur un seuil : la barre repart de zéro, elle ne reste pas pleine.
    @Test func progressResetsAtEachThreshold() {
        #expect(ExplorerGrade.forFound(40).progress(found: 40) == 0)
        #expect(ExplorerGrade.forFound(40).remainingToNext(found: 40) == 60)
    }

    /// Toutes distinctes et toutes préfixées : le test de couverture de
    /// localisation ne voit que ce qui existe dans le catalogue, pas ce qu'on
    /// a oublié de nommer.
    @Test func nameKeysAreDistinctAndPrefixed() {
        let keys = ExplorerGrade.allCases.map(\.nameKey)
        #expect(Set(keys).count == ExplorerGrade.allCases.count)
        #expect(keys.allSatisfy { $0.hasPrefix("profile.explorerGrade.") })
    }
}
