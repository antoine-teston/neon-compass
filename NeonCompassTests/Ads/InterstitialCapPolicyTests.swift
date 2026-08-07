import Testing
@testable import NeonCompass

struct InterstitialCapPolicyTests {
    @Test func allowsShowingOnceAtSessionStart() {
        #expect(InterstitialCapPolicy.shouldShow(sessionShownCount: 0, isDuringContribution: false, serverFrequency: 1))
    }

    @Test func deniesASecondShowInTheSameSession() {
        #expect(!InterstitialCapPolicy.shouldShow(sessionShownCount: 1, isDuringContribution: false, serverFrequency: 1))
    }

    @Test func deniesDuringAContributionRegardlessOfSessionCount() {
        #expect(!InterstitialCapPolicy.shouldShow(sessionShownCount: 0, isDuringContribution: true, serverFrequency: 1))
    }

    @Test func serverFrequencyZeroDisablesInterstitialsEntirely() {
        #expect(!InterstitialCapPolicy.shouldShow(sessionShownCount: 0, isDuringContribution: false, serverFrequency: 0))
    }

    @Test func negativeSessionCountIsTreatedAsZeroShown() {
        // Defensive: a caller should never pass a negative count, but the
        // policy must not accidentally allow unlimited shows if one slips
        // through — verifies the comparison is `< 1`, not `== 0`.
        #expect(InterstitialCapPolicy.shouldShow(sessionShownCount: -1, isDuringContribution: false, serverFrequency: 1))
    }
}
