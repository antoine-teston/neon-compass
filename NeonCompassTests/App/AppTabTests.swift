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

    /// La carte est au centre, et c'est structurel : `CompactTabBar` la rend
    /// comme un bouton proéminent à part des autres.
    ///
    /// Ce test RESTAURE une couverture qui existait avant le plan A, sous le nom
    /// `fiveTabsWithMapInCenter` : ce plan-là a ramené la barre à quatre onglets,
    /// rendant caduques ses assertions `count == 5` et `tabs[2] == .map`. Le
    /// cinquième onglet les rétablit, et ce test empêche d'y revenir sans s'en
    /// apercevoir. La troisième assertion de l'ancien test (`first == .feed`) a
    /// survécu séparément sous le nom `feedComesFirst`.
    @Test func mapSitsInTheMiddle() {
        let tabs = AppTab.allCases
        #expect(tabs.count == 5)
        #expect(tabs[2] == .map)
    }

    /// La barre haute est partout SAUF sur la carte, qui se joue en plein écran.
    ///
    /// Écrit dans les deux sens délibérément : une propriété qui rendrait `true`
    /// partout satisfait la moitié d'un tel test, et c'est exactement l'erreur
    /// qu'un `self != .map` mal recopié produit.
    @Test func everyTabButTheMapHasAHeaderBar() {
        #expect(!AppTab.map.showsHeaderBar)
        for tab in AppTab.allCases where tab != .map {
            #expect(tab.showsHeaderBar, "\(tab.rawValue) devrait porter la barre haute")
        }
    }
}
