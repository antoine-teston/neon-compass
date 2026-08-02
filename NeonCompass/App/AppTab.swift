import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case feed, cheats, map, profile

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .feed: "tab.feed"
        case .cheats: "tab.cheats"
        case .map: "tab.map"
        case .profile: "tab.profile"
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "newspaper"
        case .cheats: "gamecontroller"
        case .map: "map.fill"
        case .profile: "person.crop.circle"
        }
    }
}
