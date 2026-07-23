import AppTrackingTransparency
import Foundation
import Observation

@Observable
@MainActor
final class OnboardingModel {
    private static let disclaimerKey = "hasAcceptedDisclaimer"
    private static let attPromptShownKey = "hasShownATTPrompt"
    private let defaults: UserDefaults
    var needsDisclaimer: Bool
    private(set) var needsATTPrompt: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        needsDisclaimer = !defaults.bool(forKey: Self.disclaimerKey)
        needsATTPrompt = !defaults.bool(forKey: Self.attPromptShownKey)
    }

    func acceptDisclaimer() {
        defaults.set(true, forKey: Self.disclaimerKey)
        needsDisclaimer = false
    }

    // Apple's system prompt can only ever be shown once per install (a
    // second call returns the cached status silently, no dialog) — this
    // flag exists purely to skip re-presenting OUR onboarding step, not to
    // work around Apple's own one-shot behavior.
    func requestTrackingAuthorization() async {
        _ = await ATTrackingManager.requestTrackingAuthorization()
        defaults.set(true, forKey: Self.attPromptShownKey)
        needsATTPrompt = false
    }
}
