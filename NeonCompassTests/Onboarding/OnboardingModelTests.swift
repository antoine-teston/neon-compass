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
}
