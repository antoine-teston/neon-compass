@preconcurrency import FirebaseRemoteConfig

/// Lit `backendFeaturesEnabled` dans Remote Config.
///
/// Contrairement à `RemoteConfigCommunityGateProvider`, une clé absente vaut
/// **faux** : tant que le paramètre n'a pas été explicitement posé à `true`, on
/// considère que les Cloud Functions ne sont pas déployées. C'est le défaut
/// sûr — voir `ServerFeatureGateProviding` pour pourquoi les deux portails ont
/// des défauts opposés.
final class RemoteConfigServerFeatureGate: ServerFeatureGateProviding {
    nonisolated(unsafe) private let remoteConfig: RemoteConfig

    init(remoteConfig: RemoteConfig = RemoteConfig.remoteConfig()) {
        self.remoteConfig = remoteConfig
    }

    func isEnabled() async throws -> Bool {
        _ = try await remoteConfig.fetchAndActivate()
        // `boolValue` d'une clé jamais fetchée vaut déjà false ; on n'a donc
        // aucun cas particulier à traiter, contrairement au coupe-circuit qui
        // doit distinguer « absent » de « explicitement faux ».
        return remoteConfig.configValue(forKey: "backendFeaturesEnabled").boolValue
    }
}
