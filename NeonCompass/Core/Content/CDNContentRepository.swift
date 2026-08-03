import Foundation

/// Lit une collection depuis le CDN.
///
/// Il n'y a plus de repli réseau, et ce n'est pas un affaiblissement : le filet
/// est le socle embarqué dans le binaire fusionné au cache SwiftData de la
/// dernière synchronisation (`ContentStore`). Une panne du CDN dégrade vers
/// « le contenu d'hier », là où un second dépôt réseau n'aurait fait que
/// déplacer le point de panne. La vraie porte de sortie est ailleurs, et elle
/// est meilleure : `contentBaseURL` se change à distance, donc on repointe vers
/// un autre hébergeur sans mise à jour de l'app.
final class CDNContentRepository<Item: ContentItem>: ContentRemoteRepository {
    private let collectionName: String
    private let cdn: ContentCDN

    init(collectionName: String, cdn: ContentCDN = .shared) {
        self.collectionName = collectionName
        self.cdn = cdn
    }

    func fetchAll() async throws -> [Item] {
        // La source doit être décidée AVANT qu'on demande si elle l'est : sinon
        // l'écran qui gagne la course au lancement conclut « pas de CDN ».
        await ContentSourceConfigurator.ready()
        guard await cdn.isConfigured() else { throw ContentCDNError.notConfigured }
        let bundles: [ContentBundle<Item>] = try await cdn.bundles(for: collectionName)
        return bundles.flatMap(\.items)
    }
}

/// Version d'une collection, lue dans le manifeste du CDN.
///
/// Par collection, et c'est le point : la version était globale, donc une
/// publication d'actu faisait retélécharger les POI à tout le monde. Ici, une
/// collection inchangée garde sa version, `ContentStore.sync` voit « à jour »,
/// et rien ne part sur le réseau.
///
/// Zéro tant que le CDN n'est pas configuré : `ContentStore` ne déclenche alors
/// aucun téléchargement et vit sur son cache, plutôt que de l'écraser avec du
/// vide.
struct CDNContentVersionProvider: ContentVersionProviding {
    private let collectionName: String
    private let cdn: ContentCDN

    init(collectionName: String, cdn: ContentCDN = .shared) {
        self.collectionName = collectionName
        self.cdn = cdn
    }

    func invalidate() async {
        await cdn.invalidateManifest()
    }

    func currentVersion() async throws -> Int {
        await ContentSourceConfigurator.ready()
        guard await cdn.isConfigured() else { return 0 }
        return try await cdn.version(for: collectionName)
    }
}

/// Fragments de spots communautaires, servis par le CDN comme le reste.
///
/// **Manifeste séparé, et c'est délibéré.** Ils sont reconstruits au fil des
/// approbations — une tâche planifiée aux cinq minutes — pendant que le contenu
/// éditorial est publié à la main. Deux producteurs sur un même fichier de
/// manifeste, c'est une course à la clé perdue d'avance ; deux fichiers
/// indépendants n'en ont aucune. C'est le même raisonnement qui avait donné un
/// document de version distinct côté Firestore.
final class CommunityBundleRepository<Item: ContentItem>: ContentRemoteRepository {
    private let cdn: ContentCDN

    init(cdn: ContentCDN = .shared) {
        self.cdn = cdn
    }

    func fetchAll() async throws -> [Item] {
        await ContentSourceConfigurator.ready()
        guard await cdn.isConfigured() else { throw ContentCDNError.notConfigured }
        let bundles: [ContentBundle<Item>] = try await cdn.communityBundles()
        return bundles.flatMap(\.items)
    }
}

struct CommunityBundleVersionProvider: ContentVersionProviding {
    /// Valeur du champ `collection` des fragments, et clé du cache SwiftData.
    /// Doit rester identique à `BUNDLE_COLLECTION` côté serveur — la valeur est
    /// dupliquée des deux côtés d'une frontière réseau, un test la fige.
    static let collectionName = "community_spots"

    private let cdn: ContentCDN

    init(cdn: ContentCDN = .shared) {
        self.cdn = cdn
    }

    func invalidate() async {
        await cdn.invalidateCommunityManifest()
    }

    func currentVersion() async throws -> Int {
        await ContentSourceConfigurator.ready()
        guard await cdn.isConfigured() else { return 0 }
        return try await cdn.communityVersion()
    }
}
