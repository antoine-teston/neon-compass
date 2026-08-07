import Foundation
import Testing
@testable import NeonCompass

/// Doublure locale d'`AppConfigReading`. Les trois cas qui comptent — absent,
/// présent, illisible — sont exactement ceux que le protocole distingue, et
/// aucun ne demande de réseau.
private struct StubAppConfig: AppConfigReading {
    var intValue: Int?
    var throwsOnRead = false

    func bool(_ key: String, default defaultValue: Bool) async throws -> Bool {
        defaultValue
    }

    func string(_ key: String) async throws -> String? { nil }

    func int(_ key: String) async throws -> Int? {
        if throwsOnRead { throw URLError(.notConnectedToInternet) }
        return intValue
    }
}

struct InterstitialFrequencyGateTests {
    @Test func anExplicitValueIsUsedAsIs() async {
        let gate = SupabaseInterstitialFrequencyGate(config: StubAppConfig(intValue: 0))
        #expect(await gate.frequency() == 0)
    }

    /// Aucune ligne pour la clé : le format reste actif. Ce défaut est OUVERT,
    /// à l'inverse de `SupabaseServerFeatureGate` — celui-ci décrit une capacité
    /// qui existe déjà, pas une qui n'est pas déployée.
    ///
    /// L'assertion porte sur la CONSÉQUENCE et non sur `defaultFrequency` :
    /// comparer la valeur rendue à la constante qui la produit serait vrai quelle
    /// que soit cette constante, zéro compris — c'est-à-dire un défaut fermé qui
    /// passerait le test sans qu'on le voie.
    @Test func anAbsentKeyLeavesInterstitialsOn() async {
        let gate = SupabaseInterstitialFrequencyGate(config: StubAppConfig(intValue: nil))
        let frequency = await gate.frequency()
        #expect(InterstitialCapPolicy.shouldShow(
            sessionShownCount: 0,
            isDuringContribution: false,
            serverFrequency: frequency
        ))
    }

    /// Une coupure réseau ne doit pas éteindre un format qui fonctionne : ce
    /// serait couper le revenu au moment précis où le réseau est mauvais.
    @Test func anUnreadableConfigLeavesInterstitialsOn() async {
        let gate = SupabaseInterstitialFrequencyGate(config: StubAppConfig(intValue: 3, throwsOnRead: true))
        let frequency = await gate.frequency()
        #expect(InterstitialCapPolicy.shouldShow(
            sessionShownCount: 0,
            isDuringContribution: false,
            serverFrequency: frequency
        ))
    }
}
