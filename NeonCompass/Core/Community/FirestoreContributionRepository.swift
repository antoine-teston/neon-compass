import FirebaseFirestore

/// Décode toujours via document.data(as:) (Codable natif Firestore),
/// jamais JSONSerialization.data(withJSONObject:) — contributions a un
/// champ createdAt: Timestamp, non sérialisable par JSONSerialization, qui
/// lève une exception Objective-C non rattrapable (bug corrigé au Plan 5
/// sur FirestoreProfileRepository).
final class FirestoreContributionRepository: ContributionRepository {
    /// Miroir du document Firestore, sans l'id (qui vient de document.documentID,
    /// pas du corps du document).
    private struct Body: Decodable {
        let authorUid: String?
        let authorHandle: String
        let category: POICategory
        let title: String
        let languageCode: String
        let position: NormalizedPoint
        let status: Contribution.Status
        let upvotes: Int
        let downvotes: Int
    }

    nonisolated(unsafe) private let collection: CollectionReference
    private let typeName = "Contribution"

    init(firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection("contributions")
    }

    /// Plus de `fetchApproved` ici : cette requête lisait TOUTE la collection à
    /// chaque lancement de l'app, sans pagination ni cache — Firestore facturant
    /// une lecture par document, son coût valait
    /// `utilisateurs × lancements × spots`. Les spots approuvés arrivent
    /// maintenant par les fragments (`CommunityBundleVersionProvider`,
    /// `ChunkedContentRepository`).
    func fetchMine(uid: String) async throws -> [Contribution] {
        let snapshot = try await collection
            .whereField("authorUid", isEqualTo: uid)
            .getDocuments()
        return decode(snapshot.documents)
    }

    private func decode(_ documents: [QueryDocumentSnapshot]) -> [Contribution] {
        documents.compactMap { document in
            do {
                let body = try document.data(as: Body.self)
                return Contribution(
                    id: document.documentID,
                    authorUid: body.authorUid,
                    authorHandle: body.authorHandle,
                    category: body.category,
                    title: body.title,
                    languageCode: body.languageCode,
                    position: body.position,
                    status: body.status,
                    upvotes: body.upvotes,
                    downvotes: body.downvotes
                )
            } catch {
                // A single malformed document must not blank the whole
                // result — same tolerance policy as FirestoreContentRepository.
                print("FirestoreContributionRepository: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
