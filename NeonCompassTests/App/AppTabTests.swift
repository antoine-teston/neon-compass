import Testing
@testable import NeonCompass

struct AppTabTests {
    /// L'onglet Défis a fusionné dans le Profil (plan A). Ce test est ce qui
    /// empêche de le réintroduire par accident.
    @Test func progressTabIsGone() {
        #expect(!AppTab.allCases.contains { $0.rawValue == "progress" })
    }
}
