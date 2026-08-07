import Foundation
import Testing
@testable import NeonCompass

private struct StubConsent: ConsentProviding {
    var granted: Bool
    var throwsOnRequest = false

    func requestConsent() async throws -> Bool {
        if throwsOnRequest { throw URLError(.timedOut) }
        return granted
    }
}

@MainActor
struct OnboardingModelTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "OnboardingModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeModel(
        defaults: UserDefaults,
        granted: Bool = true,
        throwsOnRequest: Bool = false
    ) -> OnboardingModel {
        OnboardingModel(
            defaults: defaults,
            consentProvider: StubConsent(granted: granted, throwsOnRequest: throwsOnRequest)
        )
    }

    /// L'explication ATT ne doit pas apparaître au premier lancement : c'est le
    /// pire moment possible pour un opt-in, avant que l'utilisateur ait vu la
    /// moindre valeur.
    @Test func theExplainerIsNotOfferedOnTheFirstLaunch() async {
        let defaults = freshDefaults()
        let model = makeModel(defaults: defaults)
        model.acceptDisclaimer()
        model.registerLaunch()
        await model.requestConsent()
        #expect(!model.needsTrackingExplainer)
    }

    @Test func theExplainerIsOfferedOnTheSecondLaunch() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults)
        first.acceptDisclaimer()
        first.registerLaunch()
        await first.requestConsent()

        let second = makeModel(defaults: defaults)
        second.registerLaunch()
        #expect(second.needsTrackingExplainer)
    }

    /// Demander l'IDFA à quelqu'un qui vient de refuser le RGPD, c'est brûler
    /// l'unique demande que le système autorise par installation.
    @Test func aRefusedConsentNeverLeadsToTheATTPrompt() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults, granted: false)
        first.acceptDisclaimer()
        first.registerLaunch()
        await first.requestConsent()

        let second = makeModel(defaults: defaults, granted: false)
        second.registerLaunch()
        #expect(!second.needsTrackingExplainer)
    }

    /// Un UMP en échec est traité comme une absence de consentement — et il ne
    /// bloque pas l'app pour autant : la porte se résout, sans accorder.
    @Test func aFailedConsentFlowResolvesTheGateWithoutGranting() async {
        let defaults = freshDefaults()
        let model = makeModel(defaults: defaults, throwsOnRequest: true)
        model.acceptDisclaimer()
        model.registerLaunch()
        await model.requestConsent()
        #expect(!model.needsConsentPrompt)
        #expect(!model.consentGranted)
    }

    @Test func decliningTheExplainerHidesItForThisSession() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults)
        first.acceptDisclaimer()
        first.registerLaunch()
        await first.requestConsent()

        let second = makeModel(defaults: defaults)
        second.registerLaunch()
        second.deferTrackingExplainer()
        #expect(!second.needsTrackingExplainer)
    }

    /// « Plus tard » n'est pas « jamais » : rien n'est persisté, donc le
    /// lancement suivant repropose. Refuser l'explication n'est pas refuser le
    /// suivi.
    @Test func decliningIsNotPersistedAcrossLaunches() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults)
        first.acceptDisclaimer()
        first.registerLaunch()
        await first.requestConsent()

        let second = makeModel(defaults: defaults)
        second.registerLaunch()
        second.deferTrackingExplainer()

        let third = makeModel(defaults: defaults)
        third.registerLaunch()
        #expect(third.needsTrackingExplainer)
    }

    /// Une fois la boîte système passée, notre écran ne revient plus.
    @Test func theExplainerNeverReturnsOnceTheSystemPromptHasBeenShown() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults)
        first.acceptDisclaimer()
        first.registerLaunch()
        await first.requestConsent()

        // Ce que `requestTrackingAuthorization()` persiste, sans invoquer ATT :
        // le simulateur n'a pas de dialogue système sous test.
        defaults.set(true, forKey: "hasShownATTPrompt")

        let second = makeModel(defaults: defaults)
        second.registerLaunch()
        #expect(!second.needsTrackingExplainer)
    }

    /// Le compteur ne bouge qu'une fois par processus, quel que soit le nombre
    /// de fois que SwiftUI reconstruit la vue qui l'appelle.
    @Test func launchesAreCountedOncePerProcess() {
        let defaults = freshDefaults()
        let model = makeModel(defaults: defaults)
        model.registerLaunch()
        model.registerLaunch()
        model.registerLaunch()
        #expect(defaults.integer(forKey: "launchCount") == 1)
    }
}
