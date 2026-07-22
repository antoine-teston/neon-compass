import FirebaseFirestore

/// Implémentation réelle de ContentRemoteRepository, adossée à Firestore.
/// Remplace les trois implémentations dupliquées
/// (FirestorePOIRepository/FirestoreCheatRepository/FirestoreGuideRepository).
/// Ne référence jamais FirebaseApp.configure() — la configuration de l'app
/// reste centralisée au niveau App, cette classe ne fait qu'utiliser
/// Firestore.firestore() une fois l'app configurée.
///
/// Décodage tolérant document-par-document : un document malformé ne doit
/// jamais vider toute la collection.
final class FirestoreContentRepository<Item: Decodable & Sendable>: ContentRemoteRepository {
    private let collection: CollectionReference
    private let typeName: String

    init(collectionName: String, firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection(collectionName)
        typeName = String(describing: Item.self)
    }

    func fetchAll() async throws -> [Item] {
        let snapshot = try await collection.getDocuments()
        return snapshot.documents.compactMap { document in
            do {
                let data = try JSONSerialization.data(withJSONObject: document.data())
                return try JSONDecoder().decode(Item.self, from: data)
            } catch {
                // A single malformed document (bad manual edit, future schema
                // drift) must not blank the entire collection — skip it and
                // keep the rest. Firestore-side validation at publish time
                // (content-cli's validate/check-publishable) is the primary
                // defense; this is defense-in-depth for whatever slips through.
                print("FirestoreContentRepository<\(typeName)>: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
