import Foundation
import Observation

@Observable
@MainActor
final class OnboardingModel {
    private static let disclaimerKey = "hasAcceptedDisclaimer"
    private let defaults: UserDefaults
    var needsDisclaimer: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        needsDisclaimer = !defaults.bool(forKey: Self.disclaimerKey)
    }

    func acceptDisclaimer() {
        defaults.set(true, forKey: Self.disclaimerKey)
        needsDisclaimer = false
    }
}
