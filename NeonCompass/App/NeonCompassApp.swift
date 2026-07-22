import SwiftData
import SwiftUI

@main
struct NeonCompassApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FoundEntry.self, PersonalPin.self])
    }
}
