import Foundation
import SwiftData

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

/// Configure la source de contenu au lancement, depuis `app_config`.
///
/// `contentBaseURL` reste **pilotable à distance**, et c'est délibérément la
/// seule chose de cette migration qui garde une porte de sortie : changer
/// d'hébergeur de contenu ne demandera jamais une mise à jour de l'app. C'est
/// ce qui rend acceptable d'adosser le CDN au quota d'egress du projet (spec
/// D2) — si ce quota devient un problème, la sortie est une ligne de table.
enum ContentSourceConfigurator {
    /// Mémoïsée, et attendable par n'importe qui.
    ///
    /// Sans ça, la configuration était une course : `RootView` la lançait dans
    /// sa tâche pendant que chaque écran construisait déjà ses stores. L'écran
    /// qui gagnait — l'onglet par défaut, donc le fil actu — trouvait
    /// `ContentCDN` non configuré et concluait « pas de source ». Le contenu
    /// s'affichait quand même depuis le socle embarqué, mais ne se
    /// synchronisait plus de la session.
    ///
    /// `static let` est initialisé paresseusement et une seule fois : le
    /// premier appelant lance la configuration, tous les autres attendent la
    /// même.
    private static let configuration = Task { await configure() }

    /// À attendre avant toute lecture qui dépend de la source configurée.
    static func ready() async { await configuration.value }

    static func configureFromAppConfig() async { await configuration.value }

    private static func configure() async {
        // Une lecture qui échoue laisse `ContentCDN` non configuré, donc le
        // socle embarqué et le cache. C'est volontairement plus permissif que
        // les portails, qui lèvent : ici il n'y a rien à protéger — au pire on
        // affiche le contenu d'hier, ce que la panne réseau imposait de toute
        // façon.
        let raw = (try? await SupabaseAppConfig.shared.string(AppConfigKey.contentBaseURL)) ?? nil
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        await ContentCDN.shared.configure(baseURL: trimmed.isEmpty ? nil : URL(string: trimmed))
    }
}
