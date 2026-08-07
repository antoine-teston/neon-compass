import Foundation

/// La fréquence d'interstitiel, pilotée depuis `app_config`.
///
/// Zéro est le coupe-circuit : il éteint le format sans mise à jour de l'app.
///
/// **Défaut OUVERT**, comme le coupe-circuit communautaire et à l'inverse de
/// `SupabaseServerFeatureGate`. Ce dernier décrit une capacité qui n'existe pas
/// encore et doit donc échouer fermé ; celui-ci éteint une capacité qui existe,
/// et une coupure réseau ne doit pas l'éteindre — ce serait couper le revenu au
/// moment précis où le réseau est mauvais.
protocol InterstitialFrequencyProviding: Sendable {
    func frequency() async -> Int
}

struct SupabaseInterstitialFrequencyGate: InterstitialFrequencyProviding {
    static let defaultFrequency = 1

    private let config: any AppConfigReading

    init(config: any AppConfigReading = SupabaseAppConfig.shared) {
        self.config = config
    }

    func frequency() async -> Int {
        // `int(_:)` rend `Int?` ET lève : il y a donc deux échecs distincts,
        // « aucune ligne » et « table illisible ». Swift APLATIT le `try?` sur
        // un résultat déjà optionnel (SE-0230), ce qui rend ici les deux cas
        // indiscernables — et c'est acceptable parce qu'ils retombent tous deux
        // sur le même défaut ouvert. Si un jour ils devaient diverger, il
        // faudrait un `do/catch` explicite, pas un second niveau de `guard`.
        (try? await config.int(AppConfigKey.interstitialFrequency)) ?? Self.defaultFrequency
    }
}
