import Foundation
import Observation
import UIKit

/// `UserDefaults`-backed state for the Pro-exclusive accent theme and
/// alternate app icon selection. Constructed exactly once at `RootView` and
/// injected via `.environment(themeStore)`, same as `AuthModel`/
/// `ProEntitlementModel` — never a second per-screen instance. `RootView`
/// applies `themeStore.selectedTheme.accent` as the app-wide `.tint(...)`, so
/// this is what makes a Pro user's theme choice actually visible everywhere,
/// not just a persisted preference nobody reads.
@Observable
@MainActor
final class ThemeStore {
    private static let themeKey = "selectedTheme"
    private let defaults: UserDefaults

    private(set) var selectedTheme: NCTheme

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.themeKey).flatMap(NCTheme.init(rawValue:))
        self.selectedTheme = stored ?? .magentaDrift
    }

    func selectTheme(_ theme: NCTheme) {
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: Self.themeKey)
    }

    /// Sets the alternate app icon by asset-catalog icon-set name (or `nil`
    /// to revert to the primary icon). No-ops on devices/simulators that
    /// don't support alternate icons. NOTE: as of this task, no alternate
    /// icon set is declared in `project.yml`/the asset catalog yet (see
    /// `docs/ops/2026-07-23-alternate-app-icons.md`) — calling this with a
    /// name that isn't declared there will fail at the UIKit level (silently,
    /// via the completion handler) until that follow-up is done.
    func setAlternateIcon(named name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(name) { _ in }
    }
}
