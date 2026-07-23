import Foundation

/// Pure decision logic for whether an interstitial may be shown right now —
/// no AdMob/UIKit import, unit-testable without a device (spec
/// §"Stratégie de tests": "plafonnement des interstitiels" is explicitly
/// called out as unit-testable logic).
enum InterstitialCapPolicy {
    /// - Parameters:
    ///   - sessionShownCount: how many interstitials have already been shown
    ///     this app session (0 at launch).
    ///   - isDuringContribution: true while a contribution submission sheet
    ///     is presented — never interrupt that flow (spec point, Plan 5b).
    ///   - remoteConfigFrequency: the Remote Config-controlled frequency —
    ///     0 disables interstitials entirely (kill-switch style), 1 means
    ///     "eligible" subject to the session cap below, values above 1 are
    ///     reserved for a future "every Nth eligible moment" scheme and
    ///     currently treated identically to 1 (no such scheme exists yet —
    ///     see Self-Review).
    static func shouldShow(
        sessionShownCount: Int,
        isDuringContribution: Bool,
        remoteConfigFrequency: Int
    ) -> Bool {
        guard remoteConfigFrequency > 0 else { return false }
        guard !isDuringContribution else { return false }
        return sessionShownCount < 1
    }
}
