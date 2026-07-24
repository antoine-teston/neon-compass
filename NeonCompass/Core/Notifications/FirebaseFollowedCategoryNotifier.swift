import UserNotifications
@preconcurrency import FirebaseMessaging

/// Firebase Cloud Messaging-backed implementation of
/// `FollowedCategoryNotifying`. Verified against the resolved
/// `FirebaseMessaging` package's `FIRMessaging.h` and the iOS SDK's
/// `UNUserNotificationCenter.h`:
/// - `subscribeToTopic:completion:` / `unsubscribeFromTopic:completion:`
///   (single-error completion handlers) are auto-imported by Swift as
///   `subscribe(toTopic:) async throws` / `unsubscribe(fromTopic:) async throws`,
///   distinct overloads from the fire-and-forget non-async
///   `subscribeToTopic:` / `unsubscribeFromTopic:` selectors also exposed
///   in the header — `await` selects the async/throws overload.
/// - `requestAuthorizationWithOptions:completionHandler:(BOOL, NSError?)`
///   is auto-imported as `requestAuthorization(options:) async throws -> Bool`.
/// - `getNotificationSettingsWithCompletionHandler:(settings)` (no error
///   parameter) is auto-imported as `notificationSettings() async -> UNNotificationSettings`.
///
/// `FIRMessaging`/`Messaging` carries no Sendable or main-actor annotation
/// in its header, so no explicit isolation is required beyond the
/// `@preconcurrency` import (which silences the unchecked-Sendable
/// diagnostic for the type crossing into this `Sendable` conformance).
final class FirebaseFollowedCategoryNotifier: FollowedCategoryNotifying {
    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }
        if settings.authorizationStatus == .denied { return false }
        return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func subscribe(to category: POICategory) async {
        try? await Messaging.messaging().subscribe(toTopic: Self.topicName(for: category))
    }

    func unsubscribe(from category: POICategory) async {
        try? await Messaging.messaging().unsubscribe(fromTopic: Self.topicName(for: category))
    }

    private static func topicName(for category: POICategory) -> String {
        "spots-\(category.rawValue)"
    }
}
