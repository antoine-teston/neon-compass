import AppTrackingTransparency
import Foundation
import Observation

@Observable
@MainActor
final class OnboardingModel {
    private static let disclaimerKey = "hasAcceptedDisclaimer"
    private static let attPromptShownKey = "hasShownATTPrompt"
    private static let consentResolvedKey = "hasResolvedAdConsent"
    private let defaults: UserDefaults
    private let consentProvider: ConsentProviding
    var needsDisclaimer: Bool
    private(set) var needsATTPrompt: Bool
    private(set) var needsConsentPrompt: Bool

    init(defaults: UserDefaults = .standard, consentProvider: ConsentProviding = UMPConsentProvider()) {
        self.defaults = defaults
        self.consentProvider = consentProvider
        needsDisclaimer = !defaults.bool(forKey: Self.disclaimerKey)
        needsATTPrompt = !defaults.bool(forKey: Self.attPromptShownKey)
        needsConsentPrompt = !defaults.bool(forKey: Self.consentResolvedKey)
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

    // Consent is resolved at most once per install — the UMP SDK itself
    // handles re-prompting on its own schedule (e.g. EU consent expiry)
    // internally on subsequent `requestConsentInfoUpdate` calls made before
    // ad requests later in the app (Task 4/5), not via this onboarding gate.
    func requestConsent() async {
        _ = try? await consentProvider.requestConsent()
        defaults.set(true, forKey: Self.consentResolvedKey)
        needsConsentPrompt = false
    }
}
