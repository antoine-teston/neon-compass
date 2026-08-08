import Foundation

/// Les identifiants d'unité publicitaire, et la garantie qu'aucune vraie
/// publicité n'est servie en développement.
///
/// **Pourquoi une indirection plutôt que deux constantes remplacées le jour J.**
/// La règle AdMob interdit de servir et de cliquer de vraies annonces pendant le
/// développement : chaque lancement en simulateur deviendrait du trafic
/// invalide, et la sanction est la suspension du compte. Un remplacement
/// inconditionnel des identifiants de test — le « TODO » que portaient
/// `BannerAdView` et `AdMobInterstitialProvider` — est donc un piège à
/// retardement. La séparation doit exister AVANT que les vrais identifiants
/// n'arrivent, sans quoi elle n'existera jamais.
///
/// **Pourquoi pas d'xcconfig ni de trousseau.** Ces identifiants ne sont pas des
/// secrets : ils sont lisibles dans le binaire de n'importe quelle app publiée.
/// Les cacher serait de la cérémonie sans bénéfice.
enum AdUnits {
    /// Les unités de test publiquement documentées par Google.
    /// https://developers.google.com/admob/ios/test-ads
    enum Test {
        static let banner = "ca-app-pub-3940256099942544/2934735716"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    }

    #if DEBUG
    static let banner = Test.banner
    static let interstitial = Test.interstitial
    #else
    // TODO(ops) : remplacer par les unités réelles à la création du compte AdMob.
    // Tant qu'elles valent les unités de test, une Release ne rapporte rien —
    // c'est visible dans la console AdMob, et c'est le bon défaut : zéro revenu
    // vaut mieux qu'un compte suspendu.
    static let banner = Test.banner
    static let interstitial = Test.interstitial
    #endif
}
