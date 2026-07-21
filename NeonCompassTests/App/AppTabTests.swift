import Testing
@testable import NeonCompass

struct AppTabTests {
    @Test func fiveTabsWithMapInCenter() {
        let tabs = AppTab.allCases
        #expect(tabs.count == 5)
        #expect(tabs[2] == .map)
        #expect(tabs.first == .feed)
    }

    @Test @MainActor func defaultTabIsFeed() {
        #expect(AppModel().selectedTab == .feed)
    }
}
