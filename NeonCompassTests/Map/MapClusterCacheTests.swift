import Testing
import CoreGraphics
@testable import NeonCompass

/// Un cache d'agrégation mal invalidé ne ralentit rien : il fait DISPARAÎTRE
/// des pastilles, ou en affiche de périmées. C'est plus grave que le coût qu'il
/// supprime, d'où cette suite.
@MainActor
struct MapClusterCacheTests {
    private static let contentSize: CGFloat = 2048

    private func poi(_ id: String, _ x: Double, _ y: Double, _ category: POICategory = .landmark) -> POI {
        POI(id: id, category: category, position: NormalizedPoint(x: x, y: y),
            title: LocalizedText(en: id, fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    private func spot(_ id: String, _ x: Double, _ y: Double, upvotes: Int = 0) -> Contribution {
        Contribution(
            id: id, authorUid: "author-\(id)", authorHandle: "NEON-FALCON-88",
            category: .landmark, title: id, languageCode: "fr",
            position: NormalizedPoint(x: x, y: y), status: .approved,
            upvotes: upvotes, downvotes: 0
        )
    }

    private func cached(_ items: [POI], zoom: CGFloat, generation: Int) -> [POICluster] {
        MapClusterCache.clusters(
            items: items, zoomScale: zoom, contentSize: Self.contentSize, generation: generation
        )
    }

    // MARK: - Le cache ne doit jamais changer le résultat

    /// La garantie qui compte avant toutes les autres : à génération neuve, le
    /// cache rend exactement ce que le clusteriseur aurait rendu. Balayé sur
    /// toute la plage de zoom utile, seuil de désagrégation compris.
    @Test func cachedResultMatchesTheUncachedOneAtEveryZoom() {
        MapClusterCache.reset()
        let items = (0..<40).map { poi("p\($0)", Double($0) / 40, Double($0 % 7) / 7) }
        var generation = 0
        for zoom in stride(from: 0.4, through: 2.5, by: 0.1) {
            generation += 1
            let viaCache = cached(items, zoom: CGFloat(zoom), generation: generation)
            let direct = MapClusterer.clusters(
                items: items, zoomScale: CGFloat(zoom), contentSize: Self.contentSize
            )
            #expect(viaCache == direct, "zoom \(zoom) : le cache diverge du calcul direct")
        }
    }

    // MARK: - Invalidation

    @Test func aNewGenerationRecomputesRatherThanServingTheOldPoints() {
        MapClusterCache.reset()
        let before = cached([poi("a", 0.1, 0.1)], zoom: 1, generation: 1)
        #expect(before.flatMap { $0.members.map(\.id) } == ["a"])

        let after = cached([poi("a", 0.1, 0.1), poi("b", 0.9, 0.9)], zoom: 1, generation: 2)
        #expect(Set(after.flatMap { $0.members.map(\.id) }) == ["a", "b"])
    }

    /// Le cas qui justifie que la génération bouge même quand la COMPOSITION ne
    /// change pas : un vote ne touche que les compteurs portés par un membre,
    /// et c'est ce membre que la pastille rend.
    @Test func aNewGenerationSurfacesAChangedMemberEvenWhenMembershipIsIdentical() {
        MapClusterCache.reset()
        let first = MapClusterCache.clusters(
            items: [spot("s1", 0.5, 0.5, upvotes: 0)], zoomScale: 1,
            contentSize: Self.contentSize, keyPrefix: "s", generation: 1
        )
        #expect(first.first?.members.first?.upvotes == 0)

        let second = MapClusterCache.clusters(
            items: [spot("s1", 0.5, 0.5, upvotes: 12)], zoomScale: 1,
            contentSize: Self.contentSize, keyPrefix: "s", generation: 2
        )
        #expect(second.first?.members.first?.upvotes == 12)
    }

    // MARK: - Le piège du seuil de désagrégation

    /// Zoom 1,9 et zoom 2,0 tombent tous deux au niveau quantifié 2 — mais le
    /// premier passe par la grille et le second rend chaque point séparément.
    /// Une clé de cache réduite au niveau les confondrait, et les points
    /// resteraient groupés au-delà du seuil.
    @Test func theDisaggregationThresholdIsPartOfTheKeyEvenThoughTheLevelIsIdentical() {
        #expect(MapClusterer.level(for: 1.9) == MapClusterer.level(for: 2.0))

        MapClusterCache.reset()
        let touching = [poi("a", 0.500, 0.500), poi("b", 0.501, 0.500)]
        let aggregated = cached(touching, zoom: 1.9, generation: 1)
        let disaggregated = cached(touching, zoom: 2.0, generation: 1)

        #expect(aggregated.count == 1, "sous le seuil, les deux points forment une pastille")
        #expect(disaggregated.count == 2, "au seuil, chaque point se rend séparément")
    }

    // MARK: - Les deux familles ne se répondent pas l'une pour l'autre

    /// POI et contributions sont agrégés séparément et tombent souvent dans la
    /// même cellule : à génération et forme identiques, leurs entrées ne
    /// doivent pas se confondre.
    @Test func thePOIFamilyNeverAnswersForTheContributionOne() {
        MapClusterCache.reset()
        let pois = cached([poi("p", 0.5, 0.5)], zoom: 1, generation: 1)
        let spots = MapClusterCache.clusters(
            items: [spot("s", 0.5, 0.5)], zoomScale: 1,
            contentSize: Self.contentSize, keyPrefix: "s", generation: 1
        )
        #expect(pois.flatMap { $0.members.map(\.id) } == ["p"])
        #expect(spots.flatMap { $0.members.map(\.id) } == ["s"])
    }

    // MARK: - Stabilité

    /// Deux lectures identiques rendent la même chose — c'est ce qui évite que
    /// `ForEach` recrée toutes ses vues d'un rendu à l'autre.
    @Test func repeatedReadsAreIdentical() {
        MapClusterCache.reset()
        let items = (0..<20).map { poi("p\($0)", Double($0) / 20, 0.5) }
        let first = cached(items, zoom: 1, generation: 7)
        let second = cached(items, zoom: 1, generation: 7)
        #expect(first == second)
        #expect(first.map(\.id) == second.map(\.id))
    }
}
