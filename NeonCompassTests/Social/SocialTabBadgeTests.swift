import Testing
@testable import NeonCompass

struct SocialTabBadgeTests {
    @Test func newWeekShowsTheDot() {
        #expect(SocialTabBadge.showsDot(currentWeekID: "online_w33", lastSeenID: "online_w32"))
        #expect(SocialTabBadge.showsDot(currentWeekID: "online_w33", lastSeenID: nil))
    }

    @Test func seenWeekHidesTheDot() {
        #expect(!SocialTabBadge.showsDot(currentWeekID: "online_w33", lastSeenID: "online_w33"))
    }

    /// Aucune semaine publiée : rien à signaler — un point qui mène à un état
    /// vide serait un mensonge.
    @Test func noWeekNeverShowsTheDot() {
        #expect(!SocialTabBadge.showsDot(currentWeekID: nil, lastSeenID: nil))
        #expect(!SocialTabBadge.showsDot(currentWeekID: nil, lastSeenID: "online_w32"))
    }
}
