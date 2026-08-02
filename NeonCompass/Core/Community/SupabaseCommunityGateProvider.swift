import Foundation

/// Lit `communityContributionsEnabled` dans `app_config` — le coupe-circuit.
///
/// **Défaut OUVERT** : pas de ligne = activé. C'est un interrupteur d'urgence
/// sur une capacité qui existe, et ne pas l'avoir créé ne doit pas éteindre la
/// fonctionnalité.
///
/// Ce que la table simplifie ici. `RemoteConfigCommunityGateProvider` devait
/// distinguer « clé jamais posée » de « clé posée à faux », que l'API rendait
/// toutes deux comme `boolValue == false` — d'où l'inspection de
/// `ConfigValue.source == .static` et son commentaire d'excuse. Une ligne
/// absente est une ligne absente : `bool(_:default:)` rend le défaut, et
/// `default: true` dit tout ce qu'il y a à dire.
///
/// À ne pas confondre avec un défaut sur erreur : une lecture qui échoue lève,
/// elle ne rend pas `true`. Rallumer les contributions parce que le réseau est
/// tombé serait exactement le contraire de ce qu'un coupe-circuit doit faire.
struct SupabaseCommunityGateProvider: CommunityGateProviding {
    private let config: any AppConfigReading

    init(config: any AppConfigReading = SupabaseAppConfig.shared) {
        self.config = config
    }

    func isEnabled() async throws -> Bool {
        try await config.bool(AppConfigKey.communityContributionsEnabled, default: true)
    }
}
