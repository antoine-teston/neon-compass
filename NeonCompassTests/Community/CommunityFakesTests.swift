import Foundation
import SwiftData
import Testing
@testable import NeonCompass

final class FakeContributionRepository: ContributionRepository {
    nonisolated(unsafe) var mineToReturn: [Contribution] = []

    func fetchMine(uid: String) async throws -> [Contribution] { mineToReturn }
}

final class FakeContributionFunctions: ContributionFunctionsCalling {
    nonisolated(unsafe) private(set) var submitCallCount = 0
    nonisolated(unsafe) private(set) var lastVote: (spotId: String, direction: VoteDirection)?
    nonisolated(unsafe) private(set) var lastReport: (spotId: String, reason: String?)?

    func submitContribution(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        submitCallCount += 1
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

private func makeSpot(id: String, authorUid: String?) -> Contribution {
    Contribution(
        id: id,
        authorUid: authorUid,
        authorHandle: "NEON-FALCON-88",
        category: .landmark,
        title: "A great spot",
        languageCode: "en",
        position: NormalizedPoint(x: 0.5, y: 0.5),
        status: .approved,
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
}
