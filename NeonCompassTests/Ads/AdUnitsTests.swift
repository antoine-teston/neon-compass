import Testing
@testable import NeonCompass

struct AdUnitsTests {
    /// Les tests tournent en Debug. Si quelqu'un place un identifiant réel dans
    /// la branche Debug, cette assertion tombe — AVANT que le simulateur ne
    /// produise du trafic invalide et ne fasse suspendre le compte AdMob.
    /// C'est le seul test de ce plan dont l'absence coûterait un compte.
    @Test func debugBuildsOnlyEverUseGoogleTestUnits() {
        #expect(AdUnits.banner == AdUnits.Test.banner)
        #expect(AdUnits.interstitial == AdUnits.Test.interstitial)
    }

    /// Le préfixe éditeur des unités de test publiques de Google. L'affirmer
    /// évite qu'une faute de frappe dans un identifiant de test passe pour un
    /// identifiant valide : une unité inexistante ne remplit jamais, et le
    /// symptôme serait « la bannière ne s'affiche plus », pas « mauvais ID ».
    @Test func testUnitsCarryGooglesPublicPublisherPrefix() {
        #expect(AdUnits.Test.banner.hasPrefix("ca-app-pub-3940256099942544/"))
        #expect(AdUnits.Test.interstitial.hasPrefix("ca-app-pub-3940256099942544/"))
    }
}
