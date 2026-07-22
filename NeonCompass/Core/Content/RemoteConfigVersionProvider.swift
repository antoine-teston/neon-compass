@preconcurrency import FirebaseRemoteConfig

/// Implémentation réelle de ContentVersionProviding, adossée à Firebase
/// Remote Config. Ne configure jamais FirebaseApp elle-même (Task 7).
final class RemoteConfigVersionProvider: ContentVersionProviding {
    nonisolated(unsafe) private let remoteConfig: RemoteConfig

    init(remoteConfig: RemoteConfig = RemoteConfig.remoteConfig()) {
        self.remoteConfig = remoteConfig
    }

    func currentVersion() -> Int {
        Int(remoteConfig.configValue(forKey: "contentVersion").numberValue.intValue)
    }
}
