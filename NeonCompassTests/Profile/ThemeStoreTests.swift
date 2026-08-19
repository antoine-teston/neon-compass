import Testing
@testable import NeonCompass
import Foundation

@MainActor
struct ThemeStoreTests {
    /// Un domaine `UserDefaults` neuf par test. Même raison que
    /// `FollowedCategoriesStoreTests` : les domaines nommés sont écrits sur le
    /// disque du simulateur et ne sont PAS remis à zéro entre deux `xcodebuild
    /// test`, donc un nom littéral ferait lire à un test ce qu'une exécution
    /// précédente a laissé.
    private func makeSuiteDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    // MARK: - Le socle gratuit

    @Test func freshInstallStartsOnClassic() {
        let store = ThemeStore(defaults: makeSuiteDefaults())
        #expect(store.selectedTheme == .classic)
    }

    @Test func unknownStoredValueFallsBackToClassic() {
        let defaults = makeSuiteDefaults()
        // Ce qu'écrirait une version future dont on redescendrait, ou une
        // préférence corrompue.
        defaults.set("neonOverdriveXL", forKey: "selectedTheme")
        #expect(ThemeStore(defaults: defaults).selectedTheme == .classic)
    }

    @Test func selectionSurvivesANewStore() {
        let defaults = makeSuiteDefaults()
        ThemeStore(defaults: defaults).selectTheme(.sunsetOverdrive)
        #expect(ThemeStore(defaults: defaults).selectedTheme == .sunsetOverdrive)
    }

    // MARK: - Ce qui se paie

    @Test func onlyClassicIsFree() {
        #expect(NCTheme.classic.isPro == false)
        for theme in NCTheme.allCases where theme != .classic {
            #expect(theme.isPro, "\(theme.rawValue) devrait être payant")
        }
    }

    /// Le lot vendu par `paywall.feature.themes` doit rester au pluriel : si un
    /// thème payant disparaissait, la ligne du paywall mentirait.
    @Test func threeThemesArePaid() {
        #expect(NCTheme.allCases.filter(\.isPro).count == 3)
    }

    // MARK: - Le thème effectif

    @Test func entitledUserKeepsTheirPaidTheme() {
        let store = ThemeStore(defaults: makeSuiteDefaults())
        store.selectTheme(.magentaDrift)
        #expect(store.effectiveTheme(isProEntitled: true) == .magentaDrift)
    }

    @Test func lapsedSubscriptionFallsBackToClassic() {
        let store = ThemeStore(defaults: makeSuiteDefaults())
        store.selectTheme(.magentaDrift)
        #expect(store.effectiveTheme(isProEntitled: false) == .classic)
    }

    @Test func classicNeedsNoSubscription() {
        let store = ThemeStore(defaults: makeSuiteDefaults())
        #expect(store.effectiveTheme(isProEntitled: false) == .classic)
    }

    /// LE test de la règle : le repli ne doit pas EFFACER le choix payé.
    ///
    /// Une dégradation écrite sur place ferait repartir de `classic` au
    /// réabonnement, sans que l'utilisateur comprenne pourquoi son habillage
    /// n'est pas revenu. La lecture retombe, le stockage tient.
    @Test func fallbackDoesNotErasePaidChoice() {
        let defaults = makeSuiteDefaults()
        let store = ThemeStore(defaults: defaults)
        store.selectTheme(.sunsetOverdrive)

        _ = store.effectiveTheme(isProEntitled: false)   // l'abonnement expire

        #expect(store.selectedTheme == .sunsetOverdrive, "le choix stocké a été écrasé")
        #expect(defaults.string(forKey: "selectedTheme") == "sunsetOverdrive")
        #expect(store.effectiveTheme(isProEntitled: true) == .sunsetOverdrive, "le réabonnement n'a pas rendu le thème")
    }
}
