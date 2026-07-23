import Testing
@testable import NeonCompass

struct InterstitialCapPolicyTests {
    @Test func allowsShowingOnceAtSessionStart() {
        #expect(InterstitialCapPolicy.shouldShow(sessionShownCount: 0, isDuringContribution: false, remoteConfigFrequency: 1))
    }

    @Test func deniesASecondShowInTheSameSession() {
        #expect(!InterstitialCapPolicy.shouldShow(sessionShownCount: 1, isDuringContribution: false, remoteConfigFrequency: 1))
    }

    @Test func deniesDuringAContributionRegardlessOfSessionCount() {
        #expect(!InterstitialCapPolicy.shouldShow(sessionShownCount: 0, isDuringContribution: true, remoteConfigFrequency: 1))
    }

    @Test func remoteConfigZeroDisablesInterstitialsEntirely() {
        #expect(!InterstitialCapPolicy.shouldShow(sessionShownCount: 0, isDuringContribution: false, remoteConfigFrequency: 0))
    }

    @Test func negativeSessionCountIsTreatedAsZeroShown() {
        // Defensive: a caller should never pass a negative count, but the
        // policy must not accidentally allow unlimited shows if one slips
        // through — verifies the comparison is `< 1`, not `== 0`.
        #expect(InterstitialCapPolicy.shouldShow(sessionShownCount: -1, isDuringContribution: false, remoteConfigFrequency: 1))
    }
}
