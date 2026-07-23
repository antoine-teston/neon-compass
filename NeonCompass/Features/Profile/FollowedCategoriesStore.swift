import Foundation
import Observation

/// Persists which `POICategory` values the user wants push notifications
/// for, and drives the FCM topic subscribe/unsubscribe calls through
/// `FollowedCategoryNotifying`. Pro-gated at the call site (`ProfileScreen`),
/// not here — this store has no opinion about entitlement.
@Observable
@MainActor
final class FollowedCategoriesStore {
    private static let followedKey = "followedCategories"
    private let defaults: UserDefaults
    private let notifier: FollowedCategoryNotifying

    private(set) var followedCategories: Set<POICategory>

    init(defaults: UserDefaults = .standard, notifier: FollowedCategoryNotifying) {
        self.defaults = defaults
        self.notifier = notifier
        let stored = defaults.stringArray(forKey: Self.followedKey) ?? []
        followedCategories = Set(stored.compactMap(POICategory.init(rawValue:)))
    }

    func toggle(_ category: POICategory) async {
        if followedCategories.contains(category) {
            followedCategories.remove(category)
            await notifier.unsubscribe(from: category)
        } else {
            let granted = await notifier.requestPermissionIfNeeded()
            guard granted else { return }
            followedCategories.insert(category)
            await notifier.subscribe(to: category)
        }
        defaults.set(followedCategories.map(\.rawValue), forKey: Self.followedKey)
    }
}
