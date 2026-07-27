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

    func fetchAll() async throws -> [Item] {
        let snapshot = try await collection
            .whereField("collection", isEqualTo: collectionName)
            .order(by: "chunk")
            .getDocuments()

        return snapshot.documents.flatMap { document -> [Item] in
            do {
                let data = try JSONSerialization.data(withJSONObject: document.data())
                return try JSONDecoder().decode(ContentBundle<Item>.self, from: data).items
            } catch {
                print("ChunkedContentRepository<\(Item.self)>: skipping undecodable bundle \(document.documentID): \(error)")
                return []
            }
        }
    }
}
