import SwiftUI

/// A small, fixed set of Pro-exclusive accent-color alternatives. All colors
/// reuse existing `NCColor` hexes — no new palette values are introduced here,
/// and none reference any GTA/Rockstar palette by name.
enum NCTheme: String, CaseIterable, Identifiable {
    case magentaDrift
    case cyanPulse
    case sunsetOverdrive

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .magentaDrift: NCColor.sunsetMagenta
        case .cyanPulse: NCColor.neonCyan
        case .sunsetOverdrive: NCColor.sunsetOrange
        }
    }

    var nameKey: LocalizedStringKey {
        switch self {
        case .magentaDrift: "theme.magentaDrift"
        case .cyanPulse: "theme.cyanPulse"
        case .sunsetOverdrive: "theme.sunsetOverdrive"
        }
    }
}
