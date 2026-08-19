import Testing
@testable import NeonCompass

/// Reprend les assertions de `ExplorerGradeTests` — les seuils n'ont pas bougé,
/// seul le vocabulaire a changé — et y ajoute les bornes exactes, qui manquaient.
struct StreetRankTests {
    @Test func thresholdsAreTheDocumentedLadder() {
        #expect(StreetRank.allCases.map(\.threshold) == [0, 10, 40, 100, 250, 500])
    }

    /// Chaque palier a sa clé, et deux paliers ne partagent jamais la même : une
    /// clé recopiée par erreur ferait afficher le même nom sur deux paliers, ce
    /// qu'aucune assertion sur un palier isolé ne verrait.
    @Test func everyRankHasItsOwnKeyAndSymbol() {
        #expect(Set(StreetRank.allCases.map(\.nameKey)).count == StreetRank.allCases.count)
        #expect(Set(StreetRank.allCases.map(\.symbolName)).count == StreetRank.allCases.count)
    }

    // MARK: - Les bornes

    /// Un palier commence AU seuil, pas un lieu après. C'est le défaut classique
    /// d'un `>` posé là où il fallait un `>=`, et il ne se voit qu'en testant la
    /// paire (seuil − 1, seuil).
    @Test(arguments: [
        (0, StreetRank.tourist), (9, StreetRank.tourist),
        (10, StreetRank.runner), (39, StreetRank.runner),
        (40, StreetRank.getawayDriver), (99, StreetRank.getawayDriver),
        (100, StreetRank.heister), (249, StreetRank.heister),
        (250, StreetRank.lieutenant), (499, StreetRank.lieutenant),
        (500, StreetRank.kingpin), (5_000, StreetRank.kingpin),
    ])
    func eachCountFallsInItsRank(found: Int, expected: StreetRank) {
        #expect(StreetRank.forFound(found) == expected)
    }

    /// `FoundStore` ne peut pas produire un compte négatif aujourd'hui, mais un
    /// état corrompu pourrait — et un `allCases.last {}` sans repli rendrait
    /// alors `nil`, donc un plantage au déballage.
    @Test func aNegativeCountFallsBackToTheFirstRank() {
        #expect(StreetRank.forFound(-1) == .tourist)
    }

    // MARK: - La barre

    @Test func progressIsTheFractionInsideTheCurrentRank() {
        // 175 lieux : à mi-chemin entre 100 (braqueur) et 250 (lieutenant).
        #expect(StreetRank.forFound(175).progress(found: 175) == 0.5)
    }

    @Test func progressIsZeroAtTheStartOfARank() {
        #expect(StreetRank.getawayDriver.progress(found: 40) == 0)
    }

    /// Pas de suivant, donc pas de barre : afficher une barre pleine et
    /// définitive laisserait croire qu'il reste quelque chose à remplir.
    @Test func theLastRankHasNoProgressAndNoRemainder() {
        #expect(StreetRank.kingpin.next == nil)
        #expect(StreetRank.kingpin.progress(found: 900) == nil)
        #expect(StreetRank.kingpin.remainingToNext(found: 900) == nil)
    }

    @Test func remainingCountsDownToTheNextThreshold() {
        #expect(StreetRank.forFound(87).remainingToNext(found: 87) == 13)
        #expect(StreetRank.forFound(499).remainingToNext(found: 499) == 1)
    }

    /// Un compte au-delà du seuil suivant ne peut pas rendre un reste négatif —
    /// le cas n'arrive que si l'appelant demande le reste d'un palier qui n'est
    /// plus le sien, ce que la vue ne fait pas mais qu'un test pourrait.
    @Test func remainingNeverGoesNegative() {
        #expect(StreetRank.tourist.remainingToNext(found: 300) == 0)
    }
}
