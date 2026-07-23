import Foundation

/// The ONLY data a widget process ever sees — written by the main app to
/// a shared App Group UserDefaults suite, read by the widget extension's
/// TimelineProvider. Never a live SwiftData/Firestore query from the
/// widget process (Global Constraints: widgets never read SwiftData or
/// Firestore directly — a widget extension has no access to either).
///
/// This file is compiled into BOTH the NeonCompass app target and the
/// NeonCompassWidgets extension target (see `sources:` in project.yml) —
/// it lives under NeonCompassWidgets/ on disk but is not exclusive to
/// that target.
struct WidgetSummary: Codable, Sendable {
    static let appGroupID = "group.co.antoineteston.neoncompass"
    static let userDefaultsKey = "widgetSummary"

    let isProEntitled: Bool
    let overallProgress: Double
    let favoriteCheatTitle: String?

    static func load() -> WidgetSummary? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSummary.self, from: data)
    }
}
