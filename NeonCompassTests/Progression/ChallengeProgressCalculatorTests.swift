import Testing
@testable import NeonCompass

struct ChallengeProgressCalculatorTests {
    private func text(_ value: String) -> LocalizedText {
        LocalizedText(en: value, fr: nil, es: nil, it: nil, de: nil)
    }

    private func collection(
        _ id: String,
        game: MapGame = .reference,
        isChallenge: Bool = true,
        expectedCount: Int? = nil
    ) -> POICollection {
        POICollection(id: id, game: game, title: text(id), isChallenge: isChallenge, expectedCount: expectedCount)
    }

    private func poi(_ id: String, collection: String?, mergedInto: String? = nil) -> POI {
        POI(id: id, category: .collectible, collection: collection, position: nil,
            title: text(id), mergedInto: mergedInto)
    }

    @Test func countsFoundAgainstTheDeclaredTotal() {
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("scraps", expectedCount: 50)],
            pois: [poi("a", collection: "scraps"), poi("b", collection: "scraps")],
            foundIDs: ["a"]
        )
        #expect(result.count == 1)
        #expect(result[0].found == 1)
        #expect(result[0].referenced == 2)
        #expect(abs((result[0].fraction ?? 0) - 0.02) < 0.0001)
    }

    @Test func foundIsClampedToTheExpectedTotal() {
        // Un jeu de données plus riche que le total attendu ne doit pas
        // produire « 3 / 2 », ni un anneau au-delà de 100 %.
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("scraps", expectedCount: 2)],
            pois: [poi("a", collection: "scraps"), poi("b", collection: "scraps"), poi("c", collection: "scraps")],
            foundIDs: ["a", "b", "c"]
        )
        #expect(result[0].found == 2)
        #expect(result[0].fraction == 1.0)
    }

    @Test func fractionIsNilWhenTheTotalIsUnknown() {
        // L'état de GTA VI au lancement : on compte, on n'invente pas de ratio.
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("unknown", game: .leonida)],
            pois: [poi("a", collection: "unknown")],
            foundIDs: ["a"]
        )
        #expect(result[0].fraction == nil)
        #expect(result[0].found == 1)
        #expect(!result[0].isDataIncomplete)
    }

    @Test func flagsWhenOurDataLagsBehindTheGame() {
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("scraps", expectedCount: 50)],
            pois: [poi("a", collection: "scraps")],
            foundIDs: []
        )
        #expect(result[0].isDataIncomplete)
        #expect(result[0].referenced == 1)
    }

    @Test func ignoresFoundIDsThatMatchNoKnownPOI() {
        // Un POI supprimé en amont laisse un FoundEntry orphelin : sans ce
        // filtre il gonflerait le décompte au-delà du réel.
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("scraps", expectedCount: 50)],
            pois: [poi("a", collection: "scraps")],
            foundIDs: ["a", "disparu", "jamais_vu"]
        )
        #expect(result[0].found == 1)
    }

    @Test func remapsProgressRecordedOnAMergedDuplicate() {
        // Cocher un doublon avant sa fusion doit continuer de compter : sans le
        // remappage, fusionner effacerait la progression de tous ceux qui
        // l'avaient trouvé.
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("scraps", expectedCount: 50)],
            pois: [poi("canonique", collection: "scraps"),
                   poi("doublon", collection: "scraps", mergedInto: "canonique")],
            foundIDs: ["doublon"]
        )
        #expect(result[0].found == 1)
        // Le doublon ne compte plus comme une entrée à part entière.
        #expect(result[0].referenced == 1)
    }

    @Test func doesNotDoubleCountWhenBothSidesOfAMergeAreFound() {
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("scraps", expectedCount: 50)],
            pois: [poi("canonique", collection: "scraps"),
                   poi("doublon", collection: "scraps", mergedInto: "canonique")],
            foundIDs: ["doublon", "canonique"]
        )
        #expect(result[0].found == 1)
    }

    @Test func excludesCollectionsThatAreNotChallenges() {
        // « Compléter » les stations-service ne veut rien dire.
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("gas", isChallenge: false), collection("scraps", expectedCount: 50)],
            pois: [poi("a", collection: "gas")],
            foundIDs: ["a"]
        )
        #expect(result.map(\.id) == ["scraps"])
    }

    @Test func ignoresPOIsWithoutACollection() {
        let result = ChallengeProgressCalculator.challenges(
            collections: [collection("scraps", expectedCount: 50)],
            pois: [poi("orphelin", collection: nil)],
            foundIDs: ["orphelin"]
        )
        #expect(result[0].found == 0)
        #expect(result[0].referenced == 0)
    }

    @Test func overallSumsFoundOverExpectedAcrossChallenges() {
        let challenges = ChallengeProgressCalculator.challenges(
            collections: [collection("a", expectedCount: 10), collection("b", expectedCount: 30)],
            pois: [poi("a1", collection: "a"), poi("b1", collection: "b")],
            foundIDs: ["a1", "b1"]
        )
        // 2 trouvés sur 40 attendus — et non la moyenne des deux ratios.
        #expect(abs((ChallengeProgressCalculator.overall(challenges) ?? 0) - 0.05) < 0.0001)
    }

    @Test func overallIsNilWhenNoChallengeHasAKnownTotal() {
        // Afficher 0 % dirait « tu n'as rien trouvé » ; la vérité est « on ne
        // sait pas encore combien il y en a ».
        let challenges = ChallengeProgressCalculator.challenges(
            collections: [collection("unknown", game: .leonida)],
            pois: [poi("a", collection: "unknown")],
            foundIDs: ["a"]
        )
        #expect(ChallengeProgressCalculator.overall(challenges) == nil)
    }

    @Test func overallIgnoresChallengesWithoutAKnownTotal() {
        let challenges = ChallengeProgressCalculator.challenges(
            collections: [collection("known", expectedCount: 10), collection("unknown")],
            pois: [poi("k1", collection: "known"), poi("u1", collection: "unknown")],
            foundIDs: ["k1", "u1"]
        )
        #expect(abs((ChallengeProgressCalculator.overall(challenges) ?? 0) - 0.1) < 0.0001)
    }

    @Test func handlesEmptyInput() {
        #expect(ChallengeProgressCalculator.challenges(collections: [], pois: [], foundIDs: []).isEmpty)
        #expect(ChallengeProgressCalculator.overall([]) == nil)
    }
}
