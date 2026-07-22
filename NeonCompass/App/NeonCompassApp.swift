import FirebaseCore
import SwiftData
import SwiftUI

@main
struct NeonCompassApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self, TrophyProgress.self])
    }
}
