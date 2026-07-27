import Testing
import CoreGraphics
@testable import NeonCompass

/// L'agrégation était écrite pour les POI éditoriaux seulement. Les spots
/// communautaires étaient rendus un par un — autant de vues SwiftUI que de
/// spots, exactement le coût que l'agrégation avait été écrite pour éliminer.
struct CommunityClusteringTests {
    private func spot(_ id: String, _ x: Double, _ y: Double, _ category: POICategory = .landmark) -> Contribution {
        Contribution(
            id: id,
            authorUid: "author-\(id)",
            authorHandle: "NEON-FALCON-88",
            category: category,
            title: id,
            languageCode: "fr",
            position: NormalizedPoint(x: x, y: y),
            status: .approved,
            upvotes: 0,
            downvotes: 0
        )
    }

    private func poi(_ id: String, _ x: Double, _ y: Double) -> POI {
        POI(id: id, category: .landmark, position: NormalizedPoint(x: x, y: y),
            title: LocalizedText(en: id, fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func nearbySpotsAggregateAndDistantOnesDoNot() {
        let clusters = MapClusterer.clusters(
            items: [spot("a", 0.20, 0.20), spot("b", 0.201, 0.201), spot("far", 0.90, 0.90)],
            zoomScale: 0.4, contentSize: 2048
        )
        #expect(clusters.count == 2)
        #expect(clusters.contains { $0.count == 2 })
        #expect(clusters.contains { $0.single?.id == "far" })
    }

    @Test func zoomingInSplitsAggregatedSpots() {
        let spots = [spot("a", 0.500, 0.500), spot("b", 0.508, 0.500)]
        #expect(MapClusterer.clusters(items: spots, zoomScale: 0.4, contentSize: 2048).count == 1)

        let closeIn = MapClusterer.clusters(items: spots, zoomScale: 2.5, contentSize: 2048)
        #expect(closeIn.count == 2)
        #expect(closeIn.allSatisfy { $0.single != nil })
        #expect(Set(closeIn.map(\.id)) == ["a", "b"])
    }

    /// Le vrai piège de la généralisation : deux familles agrégées séparément
    /// tombent dans la MÊME cellule de grille dès qu'elles se recouvrent
    /// géographiquement — c'est même le cas normal. Sans préfixe distinct,
    /// leurs pastilles porteraient le même identifiant et SwiftUI confondrait
    /// deux vues qui n'ont rien à voir.
    @Test func poiAndCommunityBubblesNeverShareAnIdentity() {
        let position = (x: 0.5, y: 0.5)
        let poiClusters = MapClusterer.clusters(
            items: [poi("p1", position.x, position.y), poi("p2", position.x + 0.001, position.y)],
            zoomScale: 0.4, contentSize: 2048
        )
        let spotClusters = MapClusterer.clusters(
            items: [spot("s1", position.x, position.y), spot("s2", position.x + 0.001, position.y)],
            zoomScale: 0.4, contentSize: 2048, keyPrefix: "s"
        )

        #expect(poiClusters.count == 1)
        #expect(spotClusters.count == 1)
        #expect(Set(poiClusters.map(\.id)).isDisjoint(with: Set(spotClusters.map(\.id))))
    }

    @Test func everySpotEndsUpInExactlyOneAggregate() {
        let spots = (0..<200).map { spot("s\($0)", Double($0 % 20) * 0.045, Double($0 / 20) * 0.09) }
        let clusters = MapClusterer.clusters(items: spots, zoomScale: 0.45, contentSize: 2048, keyPrefix: "s")
        let ids = clusters.flatMap { $0.members.map(\.id) }
        #expect(ids.count == spots.count)
        #expect(Set(ids).count == spots.count)
    }

    /// Le bénéfice chiffré : trois mille spots ne doivent plus produire trois
    /// mille vues.
    @Test func aThousandSpotsCollapseToAHandfulOfViews() {
        let spots = (0..<1000).map { spot("s\($0)", 0.3 + Double($0 % 50) * 0.002, 0.3 + Double($0 / 50) * 0.002) }
        let clusters = MapClusterer.clusters(items: spots, zoomScale: 0.5, contentSize: 2048, keyPrefix: "s")
        #expect(clusters.count < 50, "1000 spots resserrés doivent tenir en quelques dizaines de pastilles")
    }
}
