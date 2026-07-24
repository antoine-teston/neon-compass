import UIKit
@preconcurrency import FirebaseMessaging

/// UIApplicationDelegate is required for APNs registration/FCM token
/// handoff — SwiftUI's App protocol has no direct hook for
/// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
/// Kept minimal: nothing here does app setup that belongs in
/// NeonCompassApp.init() (FirebaseApp.configure() etc. stay there).
///
/// `UIApplicationDelegate` methods are implicitly main-actor-isolated
/// (UIKit's apinotes annotate the protocol), so no explicit `@MainActor`
/// is needed here — verified via UIApplication.h's declarations for
/// `application(_:didFinishLaunchingWithOptions:)` and
/// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`,
/// both of which are called on the main thread by UIKit.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Verified against FIRMessaging.h: `APNSToken` (NS_SWIFT_NAME apnsToken)
        // is the documented manual hand-off point when app-delegate-proxy
        // swizzling isn't relied upon.
        Messaging.messaging().apnsToken = deviceToken
    }
}
