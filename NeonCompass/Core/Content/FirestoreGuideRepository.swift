import FirebaseFirestore

/// Implémentation réelle de GuideRemoteRepository. Ne référence jamais
/// FirebaseApp.configure() — la configuration de l'app reste centralisée
/// au niveau App (Task 7), cette classe ne fait qu'utiliser Firestore.firestore()
/// une fois l'app configurée.
///
/// Miroir de FirestorePOIRepository (plan 3) / FirestoreCheatRepository (plan 3b) —
/// décodage tolérant document-par-document, un document malformé ne doit
/// jamais vider toute la liste de guides.
final class FirestoreGuideRepository: GuideRemoteRepository {
    private let collection: CollectionReference

    init(firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection("guides")
    }

    func fetchAll() async throws -> [Guide] {
        let snapshot = try await collection.getDocuments()
        return snapshot.documents.compactMap { document in
            do {
                let data = try JSONSerialization.data(withJSONObject: document.data())
                return try JSONDecoder().decode(Guide.self, from: data)
            } catch {
                // A single malformed document (bad manual edit, future schema
                // drift) must not blank the entire list — skip it and keep the
                // rest. Firestore-side validation at publish time (content-cli's
                // validate/check-publishable) is the primary defense; this is
                // defense-in-depth for whatever slips through.
                print("FirestoreGuideRepository: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
