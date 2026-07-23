@preconcurrency import FirebaseRemoteConfig

final class RemoteConfigCommunityGateProvider: CommunityGateProviding {
    nonisolated(unsafe) private let remoteConfig: RemoteConfig

    init(remoteConfig: RemoteConfig = RemoteConfig.remoteConfig()) {
        self.remoteConfig = remoteConfig
    }

    func isEnabled() async throws -> Bool {
        _ = try await remoteConfig.fetchAndActivate()
        let value = remoteConfig.configValue(forKey: "communityContributionsEnabled")
        // No explicit "does this key exist" API on ConfigValue — an unset
        // key resolves boolValue to false, which would fail-closed
        // (wrong default, see this file's doc comment). Treat an empty
        // source (.static, meaning Remote Config never saw this key at
        // all) as enabled; any explicitly-fetched value is trusted as-is.
        if value.source == .static {
            return true
        }
        return value.boolValue
    }
}
