import FirebaseAppCheck
import FirebaseCore
import SwiftData
import SwiftUI

@main
struct NeonCompassApp: App {
    init() {
        // App Check must be configured BEFORE FirebaseApp.configure() —
        // registering the provider factory late means the first few
        // Firestore/Functions calls after launch go out without a token.
        AppCheck.setAppCheckProviderFactory(NeonCompassAppCheckProviderFactory())
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self, TrophyProgress.self, BlockedContributor.self])
    }
}

/// App Attest is the only provider used — it proves the request comes from
/// this app's signed binary running on a real device (spec §"Anti-spam &
/// anti-abus", point 1). No debug-token fallback is wired up in production
/// code; if a simulator smoke test is ever needed, it requires a separate
/// debug-only build configuration, not a runtime branch here.
final class NeonCompassAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}
