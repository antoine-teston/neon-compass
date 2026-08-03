import Foundation

/// Lit `backendFeaturesEnabled` dans `app_config`.
///
/// **Défaut FERMÉ** : tant que le paramètre n'a pas été explicitement posé à
/// vrai, on considère que la couche serveur n'est pas déployée. Voir
/// `ServerFeatureGateProviding` pour pourquoi les deux portails ont des défauts
/// opposés — celui-ci décrit une capacité qui n'existe pas encore, l'autre
/// éteint une capacité qui existe.
///
/// Une erreur de lecture se propage : `ServerFeaturesModel` la traduit en faux,
/// ce qui est le bon comportement ici et ne l'est pas pour le coupe-circuit.
struct SupabaseServerFeatureGate: ServerFeatureGateProviding {
    private let config: any AppConfigReading

    init(config: any AppConfigReading = SupabaseAppConfig.shared) {
        self.config = config
    }

    func isEnabled() async throws -> Bool {
        try await config.bool(AppConfigKey.backendFeaturesEnabled, default: false)
    }
}
