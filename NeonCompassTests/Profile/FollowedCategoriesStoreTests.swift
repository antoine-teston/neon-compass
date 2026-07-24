import Testing
@testable import NeonCompass
import Foundation

final class FakeFollowedCategoryNotifier: FollowedCategoryNotifying {
    nonisolated(unsafe) var permissionGranted = true
    nonisolated(unsafe) private(set) var subscribedCategories: Set<POICategory> = []

    func requestPermissionIfNeeded() async -> Bool { permissionGranted }
    func subscribe(to category: POICategory) async { subscribedCategories.insert(category) }
    func unsubscribe(from category: POICategory) async { subscribedCategories.remove(category) }
}

@MainActor
struct FollowedCategoriesStoreTests {
    /// Each test gets its own on-disk UserDefaults suite. A literal name (e.g. `#function`)
    /// would be reused verbatim on every `Scripts/test.sh` invocation against the same
    /// simulator, and `UserDefaults(suiteName:)` domains are persisted to disk in the app's
    /// data container — they are NOT reset between xcodebuild test runs. That previously let
    /// state leak across separate test-process invocations (confirmed: a stale
    /// `toggleFollowsWhenPermissionGranted().plist` was found in the simulator's Preferences
    /// directory), which flipped `toggle(.collectible)` from an insert into a spurious remove
    /// depending on what a prior run had left behind. A fresh UUID per test — matching the
    /// convention already used in CheatsModelTests/OnboardingModelTests — guarantees no run
    /// ever reads another run's leftover domain.
    private func makeSuiteDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    @Test func toggleFollowsWhenPermissionGranted() async {
        let notifier = FakeFollowedCategoryNotifier()
        let store = FollowedCategoriesStore(defaults: makeSuiteDefaults(), notifier: notifier)
        await store.toggle(.collectible)
        #expect(store.followedCategories.contains(.collectible))
        #expect(notifier.subscribedCategories.contains(.collectible))
    }

    @Test func toggleDoesNothingWhenPermissionDenied() async {
        let notifier = FakeFollowedCategoryNotifier()
        notifier.permissionGranted = false
        let store = FollowedCategoriesStore(defaults: makeSuiteDefaults(), notifier: notifier)
        await store.toggle(.collectible)
        #expect(!store.followedCategories.contains(.collectible))
    }

    @Test func togglingAnAlreadyFollowedCategoryUnfollows() async {
        let notifier = FakeFollowedCategoryNotifier()
        let store = FollowedCategoriesStore(defaults: makeSuiteDefaults(), notifier: notifier)
        await store.toggle(.collectible)
        await store.toggle(.collectible)
        #expect(!store.followedCategories.contains(.collectible))
        #expect(!notifier.subscribedCategories.contains(.collectible))
    }
}
