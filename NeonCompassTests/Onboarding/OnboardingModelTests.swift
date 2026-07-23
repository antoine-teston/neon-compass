import Testing
import Foundation
@testable import NeonCompass

@MainActor
struct OnboardingModelTests {
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        d.removePersistentDomain(forName: d.description)
        return d
    }

    @Test func needsDisclaimerOnFirstLaunch() {
        let model = OnboardingModel(defaults: freshDefaults())
        #expect(model.needsDisclaimer)
    }

    @Test func acceptPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let model = OnboardingModel(defaults: defaults)
        model.acceptDisclaimer()
        #expect(!model.needsDisclaimer)
        #expect(!OnboardingModel(defaults: defaults).needsDisclaimer)
    }

    @Test func needsATTPromptDefaultsTrueOnFreshInstall() {
        let model = OnboardingModel(defaults: freshDefaults())
        #expect(model.needsATTPrompt)
    }

    @Test func needsATTPromptFalseAfterPreviouslyShown() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasShownATTPrompt")
        let model = OnboardingModel(defaults: defaults)
        #expect(!model.needsATTPrompt)
    }
}
