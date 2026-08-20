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

    // MARK: - Le plus proche, pour désigner le départ

    @Test func nearestOfEmptyCandidatesIsNil() {
        #expect(RoutePlanner.nearest(to: NormalizedPoint(x: 0.5, y: 0.5), in: []) == nil)
    }

    /// Le seul candidat proche n'a pas de position : il ne compte pas, donc
    /// c'est le lointain — le seul avec une position — qui est rendu.
    @Test func nearestIgnoresPOIsWithNoPosition() {
        let unpositioned = POI(id: "close-but-unpositioned", category: .collectible, position: nil, title: LocalizedText(en: "close-but-unpositioned", fr: nil, es: nil, it: nil, de: nil), note: nil)
        let far = poi("far", 0.9, 0.9)
        let result = RoutePlanner.nearest(to: NormalizedPoint(x: 0, y: 0), in: [unpositioned, far])
        #expect(result?.id == "far")
    }

    /// L'attendu est au MILIEU du tableau : le test échoue si l'implémentation
    /// rendait simplement le premier ou le dernier candidat.
    @Test func nearestPicksTheClosestAmongThree() {
        let candidates = [poi("first", 0.9, 0.9), poi("middle", 0.1, 0.1), poi("last", 0.5, 0.9)]
        let result = RoutePlanner.nearest(to: NormalizedPoint(x: 0, y: 0), in: candidates)
        #expect(result?.id == "middle")
    }

    /// Le contrat dont dépend l'appelant : pas de paramètre `startingAt`, le
    /// départ de la tournée est celui qu'on place en tête du tableau d'entrée.
    @Test func greedyRouteStartsOnWhicheverPOIIsFirst() {
        let a = poi("a", 0, 0)
        let b = poi("b", 1, 0)
        let c = poi("c", 0, 1)
        let d = poi("d", 1, 1)

        let firstRoute = RoutePlanner.greedyRoute(from: [c, a, b, d])
        #expect(firstRoute.first?.id == "c")

        let secondRoute = RoutePlanner.greedyRoute(from: [d, a, b, c])
        #expect(secondRoute.first?.id == "d")
        #expect(secondRoute.first?.id != firstRoute.first?.id)
    }
}
