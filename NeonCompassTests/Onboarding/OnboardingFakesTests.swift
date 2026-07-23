import Testing
@testable import NeonCompass

final class FakeConsentProvider: ConsentProviding {
    nonisolated(unsafe) var resultToReturn = true

    func requestConsent() async throws -> Bool {
        resultToReturn
    }
}

struct OnboardingFakesTests {
    @Test func consentProviderReturnsConfiguredResult() async throws {
        let fake = FakeConsentProvider()
        fake.resultToReturn = false
        let result = try await fake.requestConsent()
        #expect(result == false)
    }
}
