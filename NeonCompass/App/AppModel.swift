import Observation

@Observable
@MainActor
final class AppModel {
    var selectedTab: AppTab = .feed
}
