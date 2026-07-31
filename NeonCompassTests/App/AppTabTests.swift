import Testing
@testable import NeonCompass

struct AppTabTests {
    /// L'onglet Défis a fusionné dans le Profil (plan A). Ce test est ce qui
    /// empêche de le réintroduire par accident.
    @Test func progressTabIsGone() {
        #expect(!AppTab.allCases.contains { $0.rawValue == "progress" })
    }

    /// L'Actu est l'écran d'accueil : elle vient en tête de la barre. Assertion
    /// rescapée d'un test que le retrait de l'onglet Défis a rendu caduc pour
    /// ses deux autres affirmations, portant sur cinq onglets.
    @Test func feedComesFirst() {
        #expect(AppTab.allCases.first == .feed)
    }

    @Test @MainActor func defaultTabIsFeed() {
        #expect(AppModel().selectedTab == .feed)
    }
}
