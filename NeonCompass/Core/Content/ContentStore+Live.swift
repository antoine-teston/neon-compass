import Foundation
import SwiftData

@preconcurrency import FirebaseRemoteConfig

extension ContentStore {
    /// Câblage de production d'une collection de contenu.
    ///
    /// Un seul endroit décide d'où vient le contenu — treize sites de
    /// construction répétaient sinon la même paire dépôt/fournisseur de version,
    /// avec autant d'occasions d'en oublier un lors d'une bascule.
    static func live(
        collectionName: String,
        seed: [Item] = [],
        modelContext: ModelContext
    ) -> ContentStore<Item> {
        ContentStore(
            collectionName: collectionName,
            seed: seed,
            remote: CDNContentRepository<Item>(
                collectionName: collectionName,
                firestoreFallback: ChunkedContentRepository<Item>(collectionName: collectionName)
            ),
            versionProvider: CDNContentVersionProvider(firestoreFallback: RemoteConfigVersionProvider()),
            modelContext: modelContext
        )
    }
}

/// Configure la source de contenu au lancement, depuis Remote Config.
///
/// `contentBaseURL` vide ou absent = tout passe par Firestore, exactement comme
/// avant. C'est ce qui rend la bascule vers le CDN réversible **sans mise à jour
/// de l'app** : une valeur à effacer, et tous les clients reviennent à l'ancienne
/// source en une minute.
enum ContentSourceConfigurator {
    /// Mémoïsée, et attendable par n'importe qui.
    ///
    /// Sans ça, la configuration était une course : `RootView` la lançait dans
    /// sa tâche pendant que chaque écran construisait déjà ses stores. L'écran
    /// qui gagnait — l'onglet par défaut, donc le fil actu — trouvait
    /// `ContentCDN` non configuré et retombait sur Firestore. Le contenu
    /// s'affichait quand même, mais en lectures facturées, là où le CDN est
    /// gratuit : exactement le coût que la bascule CDN avait supprimé.
    ///
    /// `static let` est initialisé paresseusement et une seule fois : le
    /// premier appelant lance la configuration, tous les autres attendent la
    /// même.
    private static let configuration = Task { await configure() }

    /// À attendre avant toute lecture qui dépend de la source configurée.
    static func ready() async { await configuration.value }

    static func configureFromRemoteConfig() async { await configuration.value }

    private static func configure() async {
        guard FirebaseAvailability.isConfigured else { return }
        let remoteConfig = RemoteConfig.remoteConfig()
        _ = try? await remoteConfig.fetchAndActivate()
        let raw = remoteConfig.configValue(forKey: "contentBaseURL").stringValue
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        await ContentCDN.shared.configure(baseURL: trimmed.isEmpty ? nil : URL(string: trimmed))
    }
}
