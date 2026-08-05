import Foundation
import SwiftData
import Testing
@testable import NeonCompass

final class FakeContributionRepository: ContributionRepository {
    nonisolated(unsafe) var mineToReturn: [Contribution] = []

    func fetchMine(uid: String) async throws -> [Contribution] { mineToReturn }

    nonisolated(unsafe) var votesToReturn: [String: VoteDirection] = [:]

    func fetchMyVotes(uid: String) async throws -> [String: VoteDirection] { votesToReturn }
}

final class FakeContributionFunctions: ContributionFunctionsCalling {
    nonisolated(unsafe) private(set) var submitCallCount = 0
    nonisolated(unsafe) private(set) var lastVote: (spotId: String, direction: VoteDirection)?
    nonisolated(unsafe) private(set) var lastReport: (spotId: String, reason: String?)?

    /// Le refus à opposer, pour vérifier que `submit` PROPAGE. Nil = succès.
    nonisolated(unsafe) var errorToThrow: (any Error)?

    func submitContribution(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        submitCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }

    nonisolated(unsafe) var voteResultToReturn: (upvotes: Int, downvotes: Int) = (0, 0)

    func castVote(spotId: String, direction: VoteDirection) async throws -> (upvotes: Int, downvotes: Int) {
        lastVote = (spotId, direction)
        return voteResultToReturn
    }

    func reportContribution(spotId: String, reason: String?) async throws {
        lastReport = (spotId, reason)
    }
}

final class FakeCommunityGateProvider: CommunityGateProviding {
    nonisolated(unsafe) var enabledToReturn = true

    func isEnabled() async throws -> Bool { enabledToReturn }
}

private func makeSpot(id: String, authorUid: String?, status: Contribution.Status = .approved) -> Contribution {
    Contribution(
        id: id,
        authorUid: authorUid,
        authorHandle: "NEON-FALCON-88",
        category: .landmark,
        title: "A great spot",
        languageCode: "en",
        position: NormalizedPoint(x: 0.5, y: 0.5),
        status: status,
        upvotes: 0,
        downvotes: 0
    )
}

@MainActor
struct CommunityFakesTests {
    /// Le conteneur porte `ContentCacheEntry` en plus : les spots approuvés
    /// transitent maintenant par `ContentStore`, qui y écrit son cache.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: BlockedContributor.self, ContentCacheEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeModel(
        context: ModelContext,
        repository: ContributionRepository = FakeContributionRepository(),
        functions: ContributionFunctionsCalling = FakeContributionFunctions(),
        spots: [Contribution] = [],
        remoteVersion: Int = 1
    ) -> CommunityModel {
        let remote = FakeContentRepository<Contribution>()
        remote.itemsToReturn = spots
        let versionProvider = FakeContentVersionProvider()
        versionProvider.version = remoteVersion
        return CommunityModel(
            repository: repository,
            functions: functions,
            gateProvider: FakeCommunityGateProvider(),
            modelContext: context,
            approvedStore: ContentStore<Contribution>(
                collectionName: "community_spots",
                remote: remote,
                versionProvider: versionProvider,
                modelContext: context
            )
        )
    }

    @Test func visibleSpotsExcludesBlockedAuthors() async throws {
        let context = ModelContext(try makeContainer())
        let model = makeModel(
            context: context,
            spots: [makeSpot(id: "1", authorUid: "author-a"), makeSpot(id: "2", authorUid: "author-b")]
        )

        await model.loadApprovedSpots()
        model.block(authorUid: "author-a")

        #expect(model.visibleSpots.map(\.id) == ["2"])
    }

    /// La garde de version est ce qui rend le lancement gratuit : sans nouvelle
    /// version, aucun fragment n'est téléchargé.
    @Test func doesNotDownloadWhenTheManifestVersionHasNotMoved() async throws {
        let context = ModelContext(try makeContainer())
        let model = makeModel(context: context, spots: [makeSpot(id: "1", authorUid: "a")], remoteVersion: 0)

        await model.loadApprovedSpots()

        #expect(model.visibleSpots.isEmpty)
    }

    @Test func voteCallsCastVoteWithSpotIDAndDirection() async throws {
        let functions = FakeContributionFunctions()
        let context = ModelContext(try makeContainer())
        let model = makeModel(context: context, functions: functions)
        let spot = makeSpot(id: "spot-1", authorUid: "author-a")

        await model.vote(on: spot, direction: .up)

        #expect(functions.lastVote?.spotId == "spot-1")
        #expect(functions.lastVote?.direction == .up)
    }

    /// Passe par `visibleSpots` et `blockedAuthorUIDs` — les deux seules
    /// surfaces que la production lit (la carte pour le rendu, l'écran Réglages
    /// pour la liste des auteurs masqués). Le test s'appuyait auparavant sur un
    /// accesseur `isBlocked` que rien n'appelait ailleurs, et ne vérifiait donc
    /// pas la restitution que son nom annonce.
    @Test func blockThenUnblockRestoresVisibility() async throws {
        let context = ModelContext(try makeContainer())
        let model = makeModel(
            context: context,
            spots: [makeSpot(id: "1", authorUid: "author-a"), makeSpot(id: "2", authorUid: "author-b")]
        )
        await model.loadApprovedSpots()

        model.block(authorUid: "author-a")
        #expect(model.blockedAuthorUIDs == ["author-a"])
        #expect(model.visibleSpots.map(\.id) == ["2"])

        model.unblock(authorUid: "author-a")
        #expect(model.blockedAuthorUIDs.isEmpty)
        #expect(model.visibleSpots.map(\.id).sorted() == ["1", "2"])
    }

    /// Le fragment est écrit par une Cloud Function et lu ici : les clés
    /// traversent une frontière réseau, donc l'aller-retour doit être figé.
    /// Les noms viennent de `bundleItem` dans `functions/src/communityBundles.ts`.
    @Test func decodesTheShapeTheCloudFunctionWrites() throws {
        let json = """
        {"id":"c1","authorUid":"u1","authorHandle":"NEON-FALCON-88","category":"collectible",
         "title":"Lettre sur le toit","languageCode":"fr","position":{"x":0.25,"y":0.5},
         "status":"approved","upvotes":3,"downvotes":0}
        """
        let spot = try JSONDecoder().decode(Contribution.self, from: Data(json.utf8))

        #expect(spot.id == "c1")
        #expect(spot.category == .collectible)
        #expect(spot.status == .approved)
        #expect(spot.position == NormalizedPoint(x: 0.25, y: 0.5))
        #expect(spot.upvotes == 3)
    }

    /// Un spot anonymisé (auteur supprimé) sort de la Function avec
    /// `authorUid: null` — il doit rester décodable.
    @Test func decodesAnAnonymisedSpot() throws {
        let json = """
        {"id":"c2","authorUid":null,"authorHandle":"auteur supprimé","category":"landmark",
         "title":"Spot","languageCode":"en","position":{"x":0.1,"y":0.2},
         "status":"approved","upvotes":0,"downvotes":0}
        """
        let spot = try JSONDecoder().decode(Contribution.self, from: Data(json.utf8))
        #expect(spot.authorUid == nil)
    }

    // MARK: - Mes votes

    /// Voter met `myVotes` à jour TOUT DE SUITE. Sans ça, la ligne resterait
    /// dans « À découvrir » et ses boutons sans état jusqu'au prochain
    /// chargement — donc on pourrait revoter en boucle sans le voir.
    @Test func votingRecordsMyVoteLocally() async throws {
        let context = ModelContext(try makeContainer())
        let functions = FakeContributionFunctions()
        functions.voteResultToReturn = (upvotes: 13, downvotes: 1)
        let model = makeModel(context: context, functions: functions)

        await model.vote(on: makeSpot(id: "c1", authorUid: "u1"), direction: .up)

        #expect(model.myVotes["c1"] == .up)
    }

    @Test func loadMyVotesFillsTheMap() async throws {
        let context = ModelContext(try makeContainer())
        let repository = FakeContributionRepository()
        repository.votesToReturn = ["c1": .up, "c2": .down]
        let model = makeModel(context: context, repository: repository)

        await model.loadMyVotes(uid: "u1")

        #expect(model.myVotes == ["c1": .up, "c2": .down])
    }

    /// Hors ligne, la lecture échoue : les deux sections retombent sur « tout à
    /// découvrir », ce qui est dégradé mais juste.
    @Test func aFailedVoteReadLeavesTheMapEmpty() async throws {
        let context = ModelContext(try makeContainer())
        let model = makeModel(context: context, repository: FailingContributionRepository())

        await model.loadMyVotes(uid: "u1")

        #expect(model.myVotes.isEmpty)
    }

    // MARK: - Mes propositions pas encore publiques

    @Test func submitPropagatesInsteadOfSwallowing() async throws {
        // Le défaut que tout ce chantier ferme : `try?` rendait un refus
        // identique à un succès.
        let functions = FakeContributionFunctions()
        functions.errorToThrow = ContributionSubmissionError.duplicateNearby
        let context = ModelContext(try makeContainer())
        let model = makeModel(context: context, functions: functions)

        await #expect(throws: ContributionSubmissionError.duplicateNearby) {
            try await model.submit(
                category: .safehouse, title: "Toit du parking",
                position: NormalizedPoint(x: 0.5, y: 0.5), languageCode: "fr"
            )
        }
        #expect(model.lastSubmissionAt == nil, "un envoi refusé n'arme pas le cooldown local")
    }

    @Test func aSuccessfulSubmitArmsTheLocalCooldown() async throws {
        let context = ModelContext(try makeContainer())
        let model = makeModel(context: context)

        try await model.submit(
            category: .safehouse, title: "Toit du parking",
            position: NormalizedPoint(x: 0.5, y: 0.5), languageCode: "fr"
        )

        #expect(model.lastSubmissionAt != nil)
    }

    @Test func myUnpublishedSpotsExcludesRejected() async throws {
        let context = ModelContext(try makeContainer())
        let repository = FakeContributionRepository()
        repository.mineToReturn = [
            makeSpot(id: "pending", authorUid: "me", status: .pending),
            makeSpot(id: "rejected", authorUid: "me", status: .rejected),
        ]
        let model = makeModel(context: context, repository: repository)

        await model.loadMyContributions(uid: "me")

        // Une cicatrice permanente sur la carte n'apprend rien ; le Profil porte
        // déjà ce statut.
        #expect(model.myUnpublishedSpots.map(\.id) == ["pending"])
    }

    /// Le cas qu'on oublierait, et qui ferait clignoter l'épingle : approuvée
    /// mais pas encore dans le fragment (tâche `*/5 * * * *`, drapeau `dirty`,
    /// garde de version côté app). Sans cette clause elle disparaîtrait à
    /// l'approbation pour revenir des minutes plus tard.
    @Test func myUnpublishedSpotsKeepsAnApprovedSpotTheBundleDoesNotHaveYet() async throws {
        let context = ModelContext(try makeContainer())
        let repository = FakeContributionRepository()
        repository.mineToReturn = [makeSpot(id: "fresh", authorUid: "me", status: .approved)]
        let model = makeModel(context: context, repository: repository)

        await model.loadMyContributions(uid: "me")

        #expect(model.myUnpublishedSpots.map(\.id) == ["fresh"])
    }

    @Test func aPublishedSpotLeavesMyUnpublishedSpots() async throws {
        let context = ModelContext(try makeContainer())
        let repository = FakeContributionRepository()
        repository.mineToReturn = [makeSpot(id: "1", authorUid: "me", status: .approved)]
        let model = makeModel(context: context, repository: repository, spots: [makeSpot(id: "1", authorUid: "me")])

        await model.loadMyContributions(uid: "me")
        #expect(model.myUnpublishedSpots.map(\.id) == ["1"])

        // Le fragment arrive : deux épingles au même endroit seraient un défaut.
        await model.loadApprovedSpots()
        #expect(model.myUnpublishedSpots.isEmpty)
    }

    @Test func myUnpublishedGenerationAdvancesOnEachRead() async throws {
        // Sans elle, une proposition tout juste envoyée n'atteindrait jamais le
        // moteur de carte : rien d'autre ne bouge sur une carte encore vide.
        let context = ModelContext(try makeContainer())
        let repository = FakeContributionRepository()
        repository.mineToReturn = [makeSpot(id: "1", authorUid: "me", status: .pending)]
        let model = makeModel(context: context, repository: repository)
        let before = model.myUnpublishedGeneration

        await model.loadMyContributions(uid: "me")

        #expect(model.myUnpublishedGeneration != before)
    }
}

/// Le dépôt qui tombe, pour exercer le chemin hors ligne.
private final class FailingContributionRepository: ContributionRepository {
    struct Offline: Error {}

    func fetchMine(uid: String) async throws -> [Contribution] { throw Offline() }
    func fetchMyVotes(uid: String) async throws -> [String: VoteDirection] { throw Offline() }
}
