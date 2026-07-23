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
    @Test func toggleFollowsWhenPermissionGranted() async {
        let notifier = FakeFollowedCategoryNotifier()
        let store = FollowedCategoriesStore(defaults: UserDefaults(suiteName: #function)!, notifier: notifier)
        await store.toggle(.collectible)
        #expect(store.followedCategories.contains(.collectible))
        #expect(notifier.subscribedCategories.contains(.collectible))
    }

    @Test func toggleDoesNothingWhenPermissionDenied() async {
        let notifier = FakeFollowedCategoryNotifier()
        notifier.permissionGranted = false
        let store = FollowedCategoriesStore(defaults: UserDefaults(suiteName: #function)!, notifier: notifier)
        await store.toggle(.collectible)
        #expect(!store.followedCategories.contains(.collectible))
    }

    @Test func togglingAnAlreadyFollowedCategoryUnfollows() async {
        let notifier = FakeFollowedCategoryNotifier()
        let store = FollowedCategoriesStore(defaults: UserDefaults(suiteName: #function)!, notifier: notifier)
        await store.toggle(.collectible)
        await store.toggle(.collectible)
        #expect(!store.followedCategories.contains(.collectible))
        #expect(!notifier.subscribedCategories.contains(.collectible))
    }
}
