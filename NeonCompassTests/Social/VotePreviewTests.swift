import Testing
@testable import NeonCompass

struct VotePreviewTests {
    /// « À découvrir » d'abord — l'ordre qui donne leur chance aux nouveaux
    /// spots — puis « les mieux notées » comblent jusqu'à trois.
    @Test func discoverComesFirstThenTopFills() {
        #expect(VotePreview.spots(discover: [1, 2], top: [3, 4]) == [1, 2, 3])
        #expect(VotePreview.spots(discover: [1, 2, 3, 4], top: [5]) == [1, 2, 3])
    }

    /// Tout voté : le module montre quand même les mieux notées plutôt que de
    /// disparaître — des propositions existent.
    @Test func emptyDiscoverFallsBackToTop() {
        #expect(VotePreview.spots(discover: [Int](), top: [7, 8]) == [7, 8])
    }

    @Test func emptyBothIsEmpty() {
        #expect(VotePreview.spots(discover: [Int](), top: []).isEmpty)
    }
}
