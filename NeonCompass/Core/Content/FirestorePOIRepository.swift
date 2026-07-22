import FirebaseFirestore

/// Implémentation réelle de POIRemoteRepository. Ne référence jamais
/// FirebaseApp.configure() — la configuration de l'app reste centralisée
/// au niveau App (Task 7), cette classe ne fait qu'utiliser Firestore.firestore()
/// une fois l'app configurée.
///
/// v1 : synchronisation par collection entière (pas de delta par document) —
/// suffisant tant que le nombre de POI reste modeste ; à optimiser en delta
/// document-par-document si le contenu grossit significativement.
final class FirestorePOIRepository: POIRemoteRepository {
    private let collection: CollectionReference

    init(firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection("poi")
    }

    func fetchAll() async throws -> [POI] {
        let snapshot = try await collection.getDocuments()
        return try snapshot.documents.compactMap { document in
            let data = try JSONSerialization.data(withJSONObject: document.data())
            return try JSONDecoder().decode(POI.self, from: data)
        }
    }
}
