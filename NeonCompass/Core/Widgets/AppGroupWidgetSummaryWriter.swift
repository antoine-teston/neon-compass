import Foundation
import WidgetKit

/// Writes to the App Group UserDefaults suite the widget extension reads
/// from, then asks WidgetKit to reload — without this call, a widget
/// already on the home screen keeps showing stale data until its next
/// system-scheduled refresh, which could be hours away.
///
/// `WidgetCenter` is `@unchecked Sendable` and its methods are plain,
/// non-actor-isolated instance methods — safe to call from any isolation
/// context, including the `@MainActor` models that call `write(_:)` here.
final class AppGroupWidgetSummaryWriter: WidgetSummaryWriting {
    func write(_ summary: WidgetSummary) {
        guard let defaults = UserDefaults(suiteName: WidgetSummary.appGroupID),
              let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: WidgetSummary.userDefaultsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "ProgressWidget")
    }
}
