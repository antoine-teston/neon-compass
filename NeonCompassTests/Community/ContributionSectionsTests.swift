import Foundation
import Testing
@testable import NeonCompass

struct ContributionSectionsTests {
    private func spot(
        _ id: String,
        up: Int = 0,
        down: Int = 0,
        approvedAt: String? = nil
    ) -> Contribution {
        var made = Contribution(
            id: id,
            authorUid: "u-\(id)",
            authorHandle: "NEON-FALCON-88",
            category: .landmark,
            title: "Spot \(id)",
            languageCode: "fr",
            position: NormalizedPoint(x: 0.5, y: 0.5),
            status: .approved,
            upvotes: up,
            downvotes: down
        )
        made.approvedAt = approvedAt
        return made
    }

    // MARK: - À découvrir

    /// Ce sur quoi j'ai voté quitte « À découvrir » : la section existe pour que
    /// chaque proposition passe sous mes yeux UNE fois.
    @Test func votedSpotsLeaveTheDiscoverSection() {
        let sections = ContributionSections(
            spots: [spot("a"), spot("b")],
            myVotes: ["a": .up]
        )
        #expect(sections.discover.map(\.id) == ["b"])
    }

    /// Un vote négatif compte autant qu'un positif : j'ai vu, j'ai tranché.
    @Test func aDownvoteAlsoCountsAsSeen() {
        let sections = ContributionSections(spots: [spot("a")], myVotes: ["a": .down])
        #expect(sections.discover.isEmpty)
    }

    @Test func discoverIsMostRecentFirst() {
        let sections = ContributionSections(
            spots: [
                spot("vieux", approvedAt: "2026-08-01T10:00:00Z"),
                spot("neuf", approvedAt: "2026-08-04T10:00:00Z"),
                spot("moyen", approvedAt: "2026-08-02T10:00:00Z"),
            ],
            myVotes: [:]
        )
        #expect(sections.discover.map(\.id) == ["neuf", "moyen", "vieux"])
    }

    /// Une ligne sans date vient d'un fragment mis en cache avant l'ajout de la
    /// colonne. Elle passe en fin plutôt que de disparaître ou de remonter.
    @Test func spotsWithoutADateGoLast() {
        let sections = ContributionSections(
            spots: [spot("sansDate"), spot("daté", approvedAt: "2026-08-01T10:00:00Z")],
            myVotes: [:]
        )
        #expect(sections.discover.map(\.id) == ["daté", "sansDate"])
    }

    // MARK: - Les mieux notées

    @Test func topIsSortedByScore() {
        let sections = ContributionSections(
            spots: [spot("moyen", up: 10), spot("fort", up: 50), spot("faible", up: 1)],
            myVotes: ["moyen": .up, "fort": .up, "faible": .up]
        )
        #expect(sections.top.map(\.id) == ["fort", "moyen", "faible"])
    }

    /// Le score est un solde : vingt pour et dix-neuf contre valent moins que
    /// deux pour et zéro contre.
    @Test func scoreIsUpvotesMinusDownvotes() {
        let sections = ContributionSections(
            spots: [spot("controversé", up: 20, down: 19), spot("net", up: 2)],
            myVotes: ["controversé": .up, "net": .up]
        )
        #expect(sections.top.map(\.id) == ["net", "controversé"])
    }

    /// Pas deux fois la même ligne dans un écran : ça se lit comme un défaut, et
    /// une proposition affichée deux centimètres plus haut n'a pas besoin d'une
    /// seconde apparition.
    @Test func topExcludesWhatDiscoverAlreadyShows() {
        let sections = ContributionSections(
            spots: [spot("nouveauEtAimé", up: 99, approvedAt: "2026-08-04T10:00:00Z")],
            myVotes: [:]
        )
        #expect(sections.discover.map(\.id) == ["nouveauEtAimé"])
        #expect(sections.top.isEmpty)
    }

    /// Au démarrage, TOUT est à zéro : sans départage, l'ordre changerait à
    /// chaque réévaluation de la vue et les lignes sauteraient.
    @Test func tiesAreBrokenStably() {
        let spots = [spot("c"), spot("a"), spot("b")]
        let votes: [String: VoteDirection] = ["a": .up, "b": .up, "c": .up]
        let first = ContributionSections(spots: spots, myVotes: votes)
        let second = ContributionSections(spots: spots.reversed(), myVotes: votes)
        #expect(first.top.map(\.id) == second.top.map(\.id))
        #expect(first.top.map(\.id) == ["a", "b", "c"])
    }

    // MARK: - Plafond

    @Test func theLimitAppliesPerSection() {
        let unvoted = (1...30).map { spot("d\($0)", approvedAt: "2026-08-0\(($0 % 9) + 1)T10:00:00Z") }
        let voted = (1...30).map { spot("t\($0)", up: $0) }
        var votes: [String: VoteDirection] = [:]
        for entry in voted { votes[entry.id] = .up }
        let sections = ContributionSections(spots: unvoted + voted, myVotes: votes, limit: 5)
        #expect(sections.discover.count == 5)
        #expect(sections.top.count == 5)
    }

    @Test func emptyInputGivesEmptySections() {
        let sections = ContributionSections(spots: [], myVotes: [:])
        #expect(sections.discover.isEmpty)
        #expect(sections.top.isEmpty)
    }

    /// Déconnecté, on n'a voté sur rien : tout est à découvrir.
    @Test func withoutVotesEverythingIsToDiscover() {
        let sections = ContributionSections(
            spots: [
                spot("a", approvedAt: "2026-08-01T10:00:00Z"),
                spot("b", approvedAt: "2026-08-02T10:00:00Z"),
            ],
            myVotes: [:]
        )
        #expect(sections.discover.count == 2)
        #expect(sections.top.isEmpty)
    }
}
