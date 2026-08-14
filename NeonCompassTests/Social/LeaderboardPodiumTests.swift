import Testing
@testable import NeonCompass

struct LeaderboardPodiumTests {
    private func row(_ handle: String) -> LeaderboardRow {
        LeaderboardRow(uid: handle, handle: handle, xp: 0, approvedCount: 0)
    }

    /// L'ordre d'affichage d'un podium : 2ᵉ, 1ᵉʳ (au centre, surélevé), 3ᵉ.
    @Test func threeRowsRenderSecondFirstThird() {
        let order = LeaderboardPodium.displayOrder([row("a"), row("b"), row("c")])
        #expect(order.map(\.handle) == ["b", "a", "c"])
    }

    @Test func twoRowsRenderSecondThenFirst() {
        #expect(LeaderboardPodium.displayOrder([row("a"), row("b")]).map(\.handle) == ["b", "a"])
    }

    @Test func oneRowRendersAlone() {
        #expect(LeaderboardPodium.displayOrder([row("a")]).map(\.handle) == ["a"])
    }

    /// Au-delà de trois, le podium n'affiche que le trio de tête.
    @Test func extraRowsAreIgnored() {
        let order = LeaderboardPodium.displayOrder([row("a"), row("b"), row("c"), row("d")])
        #expect(order.count == 3)
        #expect(!order.map(\.handle).contains("d"))
    }
}
