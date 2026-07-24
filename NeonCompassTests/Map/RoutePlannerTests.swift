import Testing
@testable import NeonCompass

struct RoutePlannerTests {
    private func poi(_ id: String, _ x: Double, _ y: Double) -> POI {
        POI(id: id, category: .collectible, position: NormalizedPoint(x: x, y: y), title: LocalizedText(en: id, fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func greedyRouteVisitsEveryPOIExactlyOnce() {
        let pois = [poi("a", 0, 0), poi("b", 1, 1), poi("c", 0.5, 0.5)]
        let route = RoutePlanner.greedyRoute(from: pois)
        #expect(Set(route.map(\.id)) == Set(pois.map(\.id)))
        #expect(route.count == pois.count)
    }

    @Test func greedyRoutePicksTheNearestUnvisitedNext() {
        // Starting at (0,0): nearest is (0.1,0.1), then the far one (1,1) — not the reverse.
        let pois = [poi("start", 0, 0), poi("far", 1, 1), poi("near", 0.1, 0.1)]
        let route = RoutePlanner.greedyRoute(from: pois)
        #expect(route.map(\.id) == ["start", "near", "far"])
    }

    @Test func greedyRouteSkipsPOIsWithNoPosition() {
        let noPosition = POI(id: "pending", category: .collectible, position: nil, title: LocalizedText(en: "pending", fr: nil, es: nil, it: nil, de: nil), note: nil)
        let route = RoutePlanner.greedyRoute(from: [poi("a", 0, 0), noPosition])
        #expect(route.map(\.id) == ["a"])
    }

    @Test func greedyRouteOfEmptyInputIsEmpty() {
        #expect(RoutePlanner.greedyRoute(from: []).isEmpty)
    }
}
