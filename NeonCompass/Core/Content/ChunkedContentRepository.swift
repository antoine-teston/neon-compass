import FirebaseFirestore

/// Lit une collection de contenu depuis les agrégats `content_bundles` plutôt
/// que document par document.
///
/// Remplace `FirestoreContentRepository` côté client. Les documents unitaires
/// continuent d'exister dans Firestore — ils sont la surface d'écriture du mode
/// éditeur et ce qu'on inspecte dans la console —, mais ce n'est plus ce que
/// l'app lit : à une lecture facturée par document, un bump de version coûtait
/// autant de lectures qu'il y a d'entrées, fois le nombre de clients.
///
/// Décodage tolérant fragment par fragment, même raison que dans
/// `FirestoreContentRepository` : un fragment malformé ne doit pas vider toute
/// la collection. La granularité est plus grossière (on perd jusqu'à 500 entrées
/// au lieu d'une), ce qui est le prix de l'agrégation — la validation à la
/// publication (`content-cli validate`) reste la défense principale.
final class ChunkedContentRepository<Item: ContentItem>: ContentRemoteRepository {
    private let collection: CollectionReference
    private let collectionName: String

    init(collectionName: String, firestore: Firestore = Firestore.firestore()) {
        self.collectionName = collectionName
        collection = firestore.collection("content_bundles")
    }

    /// Le tri se fait en mémoire, PAS dans la requête.
    ///
    /// `whereField` + `order(by:)` sur deux champs différents exige un index
    /// composite dans Firestore. Il n'existait pas, et le dépôt ne gère aucun
    /// `firestore.indexes.json` : toute lecture de repli échouait donc en
    /// `Code=9 — The query requires an index`. Personne ne s'en apercevait,
    /// parce que ce chemin ne sert que si le CDN est indisponible… c'est-à-dire
    /// exactement quand on n'a pas les moyens de déployer un index d'abord.
    /// Un repli conditionné à un déploiement n'est pas un repli.
    ///
    /// Le tri en mémoire est gratuit ici : il y a ⌈N/500⌉ fragments, soit un ou
    /// deux aujourd'hui.
    func fetchAll() async throws -> [Item] {
        let snapshot = try await collection
            .whereField("collection", isEqualTo: collectionName)
            .getDocuments()

        return snapshot.documents
            .compactMap { document -> ContentBundle<Item>? in
                do {
                    let data = try JSONSerialization.data(withJSONObject: document.data())
                    return try JSONDecoder().decode(ContentBundle<Item>.self, from: data)
                } catch {
                    print("ChunkedContentRepository<\(Item.self)>: skipping undecodable bundle \(document.documentID): \(error)")
                    return nil
                }
            }
            .sorted { $0.chunk < $1.chunk }
            .flatMap(\.items)
    }
}
