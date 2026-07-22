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
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, POICacheEntry.self, CheatCacheEntry.self, FavoriteCheat.self, GuideCacheEntry.self, ContentCacheEntry.self])
    }
}
