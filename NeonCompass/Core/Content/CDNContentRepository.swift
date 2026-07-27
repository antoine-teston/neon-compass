import Foundation

/// Lit une collection depuis le CDN si une URL de base est configurée, et
/// retombe sur Firestore sinon.
///
/// Le repli n'est pas une précaution timide : c'est ce qui rend la bascule
/// **réversible sans mise à jour de l'app**. Vider `contentBaseURL` dans Remote
/// Config remet tout le monde sur Firestore en une minute, ce qui est la seule
/// façon honnête d'introduire une nouvelle source de vérité en production.
final class CDNContentRepository<Item: ContentItem>: ContentRemoteRepository {
    private let collectionName: String
    private let firestoreFallback: any ContentRemoteRepository<Item>
    private let cdn: ContentCDN

    init(
        collectionName: String,
        firestoreFallback: any ContentRemoteRepository<Item>,
        cdn: ContentCDN = .shared
    ) {
        self.collectionName = collectionName
        self.firestoreFallback = firestoreFallback
        self.cdn = cdn
    }

    func fetchAll() async throws -> [Item] {
        guard await cdn.isConfigured() else {
            return try await firestoreFallback.fetchAll()
        }
        let bundles: [ContentBundle<Item>] = try await cdn.bundles(for: collectionName)
        return bundles.flatMap(\.items)
    }
}

/// Version du contenu, lue dans le manifeste du CDN quand il est configuré, et
/// dans Remote Config sinon.
///
/// Les deux sources sont volontairement le MÊME entier vu par le client : un
/// `ContentStore` ne sait pas laquelle l'alimente, et bascule de l'une à l'autre
/// sans invalider son cache — tant que la nouvelle version est supérieure.
///
/// Attention à ce dernier point : la version du CDN vient du nombre de commits
/// du dépôt, celle de Remote Config d'un compteur incrémenté à chaque
/// publication. La première est structurellement plus grande, donc passer de
/// Firestore au CDN déclenche une resynchronisation (voulu), tandis que revenir
/// en arrière laisserait le cache en place jusqu'au prochain dépassement — un
/// repli sert à éteindre un incendie, pas à revenir au contenu d'avant.
struct CDNContentVersionProvider: ContentVersionProviding {
    private let firestoreFallback: ContentVersionProviding
    private let cdn: ContentCDN

    init(firestoreFallback: ContentVersionProviding, cdn: ContentCDN = .shared) {
        self.firestoreFallback = firestoreFallback
        self.cdn = cdn
    }

    func currentVersion() async throws -> Int {
        guard await cdn.isConfigured() else {
            return try await firestoreFallback.currentVersion()
        }
        return try await cdn.manifest().version
    }
}
