import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case feed, cheats, map, social, profile

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .feed: "tab.feed"
        case .cheats: "tab.cheats"
        case .map: "tab.map"
        case .social: "tab.social"
        case .profile: "tab.profile"
        }
    }

    /// La carte est le seul écran sans barre haute.
    ///
    /// Elle se joue en plein écran — on y zoome, on y fait glisser, on y pose des
    /// épingles — et une capsule flottante y mangerait la vue au moment précis où
    /// l'on veut le plus de place. Les quatre autres écrans sont des colonnes de
    /// lecture : quelques points en haut ne leur coûtent rien.
    ///
    /// Une propriété de l'énumération plutôt qu'un `if tab == .map` enfoui dans
    /// `RootView` : c'est ce qui rend la règle testable.
    var showsHeaderBar: Bool { self != .map }

    var systemImage: String {
        switch self {
        case .feed: "newspaper"
        case .cheats: "gamecontroller"
        case .map: "map.fill"
        case .social: "person.2"
        case .profile: "person.crop.circle"
        }
    }
}
