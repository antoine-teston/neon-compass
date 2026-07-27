import Testing
import CoreGraphics
@testable import NeonCompass

struct POIClustererTests {
    private func poi(_ id: String, _ x: Double, _ y: Double, _ category: POICategory = .landmark) -> POI {
        POI(id: id, category: category, position: NormalizedPoint(x: x, y: y),
            title: LocalizedText(en: id, fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func poisWithoutPositionAreExcluded() {
        let placed = poi("a", 0.5, 0.5)
        let unplaced = POI(id: "b", category: .landmark, position: nil,
                           title: LocalizedText(en: "b", fr: nil, es: nil, it: nil, de: nil), note: nil)
        let clusters = POIClusterer.clusters(pois: [placed, unplaced], zoomScale: 1, contentSize: 2048)
        #expect(clusters.count == 1)
        #expect(clusters[0].single?.id == "a")
    }

    @Test func nearbyPOIsAggregateAndDistantOnesDoNot() {
        // Deux points quasi confondus + un à l'opposé de la carte.
        let clusters = POIClusterer.clusters(
            pois: [poi("a", 0.20, 0.20), poi("b", 0.201, 0.201), poi("far", 0.90, 0.90)],
            zoomScale: 0.4, contentSize: 2048
        )
        #expect(clusters.count == 2)
        #expect(clusters.contains { $0.count == 2 })
        #expect(clusters.contains { $0.single?.id == "far" })
    }

    // La promesse produit : l'agrégat se délie quand on zoome.
    @Test func zoomingInSplitsAggregates() {
        let pois = [poi("a", 0.500, 0.500), poi("b", 0.508, 0.500)]
        let farOut = POIClusterer.clusters(pois: pois, zoomScale: 0.4, contentSize: 2048)
        let closeIn = POIClusterer.clusters(pois: pois, zoomScale: 2.5, contentSize: 2048)
        #expect(farOut.count == 1)
        #expect(farOut[0].count == 2)
        #expect(closeIn.count == 2)
        #expect(closeIn.allSatisfy { $0.single != nil })
    }

    // Points volontairement très proches : à ce zoom la cellule fait ~124 px
    // de contenu, et deux points plus écartés peuvent tomber de part et
    // d'autre d'une frontière de grille sans pour autant être « loin ».
    // Régression : la cellule rétrécit avec le zoom, mais le zoom est plafonné.
    // Des POI quasi confondus (deux pompes d'une même station) restaient donc
    // groupés même à fond de zoom, dans une pastille qui ne s'ouvrait jamais.
    @Test func nothingStaysAggregatedPastTheDisaggregationZoom() {
        // Deux points volontairement quasi confondus.
        let pois = [poi("a", 0.5000, 0.5000), poi("b", 0.5001, 0.5000)]
        let clustered = POIClusterer.clusters(pois: pois, zoomScale: 1.5, contentSize: 2048)
        #expect(clustered.count == 1, "à zoom moyen ils doivent encore être groupés")

        let split = POIClusterer.clusters(
            pois: pois, zoomScale: POIClusterer.disaggregationZoom, contentSize: 2048
        )
        #expect(split.count == 2)
        #expect(split.allSatisfy { $0.single != nil })
    }

    @Test func disaggregatedPinsKeepTheirOwnIdentityAndCategory() {
        let pois = [poi("a", 0.5, 0.5, .collectible), poi("b", 0.5001, 0.5, .vehicle)]
        let split = POIClusterer.clusters(pois: pois, zoomScale: 2.5, contentSize: 2048)
        #expect(Set(split.map(\.id)) == ["a", "b"])
        #expect(split.first { $0.id == "a" }?.dominantCategory == .collectible)
        #expect(split.first { $0.id == "b" }?.dominantCategory == .vehicle)
    }

    @Test func aggregatePositionIsTheCentroidOfItsMembers() {
        let clusters = POIClusterer.clusters(
            pois: [poi("a", 0.300, 0.400), poi("b", 0.302, 0.404)], zoomScale: 0.3, contentSize: 2048
        )
        #expect(clusters.count == 1)
        #expect(abs(clusters[0].position.x - 0.301) < 0.0001)
        #expect(abs(clusters[0].position.y - 0.402) < 0.0001)
    }

    @Test func aggregateTakesTheColorOfItsMostFrequentCategory() {
        let clusters = POIClusterer.clusters(
            pois: [poi("a", 0.5, 0.5, .collectible),
                   poi("b", 0.501, 0.5, .collectible),
                   poi("c", 0.502, 0.5, .vehicle)],
            zoomScale: 0.3, contentSize: 2048
        )
        #expect(clusters.count == 1)
        #expect(clusters[0].dominantCategory == .collectible)
    }

    // Le zoom est quantifié en demi-octaves : sans ça les groupes se
    // scinderaient et refusionneraient à chaque frame de pincement, et les
    // compteurs clignoteraient.
    @Test func clusteringIsStableBetweenQuantizationSteps() {
        let pois = (0..<40).map { poi("p\($0)", 0.4 + Double($0) * 0.004, 0.5) }
        let a = POIClusterer.clusters(pois: pois, zoomScale: 1.00, contentSize: 2048)
        let b = POIClusterer.clusters(pois: pois, zoomScale: 1.05, contentSize: 2048)
        #expect(POIClusterer.level(for: 1.00) == POIClusterer.level(for: 1.05))
        #expect(a.map(\.id) == b.map(\.id))
    }

    /// L'ordre d'itération d'un Dictionary n'est pas garanti : un ForEach dont
    /// l'ordre change ferait recréer toutes les vues à chaque recalcul.
    @Test func outputOrderIsDeterministic() {
        let pois = (0..<60).map { poi("p\($0)", Double($0 % 10) * 0.09, Double($0 / 10) * 0.15) }
        let runs = (0..<5).map { _ in POIClusterer.clusters(pois: pois, zoomScale: 0.5, contentSize: 2048).map(\.id) }
        #expect(Set(runs).count == 1)
    }

    @Test func everyPOIEndsUpInExactlyOneAggregate() {
        let pois = (0..<200).map { poi("p\($0)", Double($0 % 20) * 0.045, Double($0 / 20) * 0.09) }
        let clusters = POIClusterer.clusters(pois: pois, zoomScale: 0.45, contentSize: 2048)
        let ids = clusters.flatMap { $0.members.map(\.id) }
        #expect(ids.count == pois.count)
        #expect(Set(ids).count == pois.count)
    }

    @Test func degenerateInputsDoNotCrash() {
        #expect(POIClusterer.clusters(pois: [], zoomScale: 1, contentSize: 2048).isEmpty)
        #expect(POIClusterer.clusters(pois: [poi("a", 0.5, 0.5)], zoomScale: 0, contentSize: 2048).isEmpty == false)
        #expect(POIClusterer.clusters(pois: [poi("a", 0.5, 0.5)], zoomScale: 1, contentSize: 0).isEmpty)
    }
}
