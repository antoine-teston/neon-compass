import Foundation

/// Abstraction over push-notification permission + per-category topic
/// subscription. No Firebase/UIKit import here — features (and Task 3's
/// `FollowedCategoriesStore`) depend on this protocol only, matching the
/// project's Core/-behind-a-protocol rule for Firebase.
protocol FollowedCategoryNotifying: Sendable {
    func requestPermissionIfNeeded() async -> Bool
    func subscribe(to category: POICategory) async
    func unsubscribe(from category: POICategory) async
}
