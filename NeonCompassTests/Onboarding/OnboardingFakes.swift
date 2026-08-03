// Doublure partagée par `OnboardingModelTests`. Aucun test ici : ce fichier ne
// porte que le fake.

@testable import NeonCompass

final class FakeConsentProvider: ConsentProviding {
    nonisolated(unsafe) var resultToReturn = true

    func requestConsent() async throws -> Bool {
        resultToReturn
    }
}
