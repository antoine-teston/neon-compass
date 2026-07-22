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
        return snapshot.documents.compactMap { document in
            do {
                let data = try JSONSerialization.data(withJSONObject: document.data())
                return try JSONDecoder().decode(POI.self, from: data)
            } catch {
                // A single malformed document (bad manual edit, future schema
                // drift) must not blank the entire map — skip it and keep the
                // rest. Firestore-side validation at publish time (content-cli's
                // validate/check-publishable) is the primary defense; this is
                // defense-in-depth for whatever slips through.
                print("FirestorePOIRepository: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
