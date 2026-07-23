@preconcurrency import FirebaseAuth
import FirebaseFirestore

/// Implémentation réelle de ProgressionSyncing. Écrit sous
/// profiles/{uid}/progression/{kind}_{itemID} — un document par item, pas
/// un blob unique, pour que le dernier-écrivain-gagne se fasse par item
/// (voir ce plan, Global Constraints) plutôt que d'écraser tout l'historique
/// d'un appareil si l'autre appareil était hors-ligne plus longtemps.
///
/// Décode toujours via document.data(as:) (Codable natif Firestore),
/// jamais JSONSerialization.data(withJSONObject:) — updatedAt est un
/// Timestamp, non sérialisable par JSONSerialization, qui lève une
/// exception Objective-C non rattrapable (bug corrigé au Plan 5 sur
/// FirestoreProfileRepository). Le décodeur Firestore convertit
/// automatiquement Timestamp -> Date (dateDecodingStrategy par défaut :
/// .timestamp), donc un simple champ `Date` dans Body suffit.
final class FirestoreProgressionSync: ProgressionSyncing {
    /// Miroir du document Firestore, sans l'id (qui vient de document.documentID,
    /// pas du corps du document).
    private struct Body: Decodable {
        let itemID: String
        let kind: ProgressionItemKind
        let found: Bool
        let updatedAt: Date
    }

    nonisolated(unsafe) private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func upload(itemID: String, kind: ProgressionItemKind, found: Bool, updatedAt: Date) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docID = "\(kind.rawValue)_\(itemID)"
        try? await firestore.collection("profiles").document(uid).collection("progression").document(docID).setData([
            "itemID": itemID,
            "kind": kind.rawValue,
            "found": found,
            "updatedAt": Timestamp(date: updatedAt),
        ])
    }

    func fetchAll(uid: String) async -> [ProgressionSyncItem] {
        guard let snapshot = try? await firestore.collection("profiles").document(uid).collection("progression").getDocuments() else {
            return []
        }
        return snapshot.documents.compactMap { document in
            do {
                let body = try document.data(as: Body.self)
                return ProgressionSyncItem(itemID: body.itemID, kind: body.kind, found: body.found, updatedAt: body.updatedAt)
            } catch {
                // A single malformed document must not blank the whole
                // result — same tolerance policy as FirestoreContentRepository
                // / FirestoreContributionRepository.
                print("FirestoreProgressionSync: skipping undecodable document \(document.documentID): \(error)")
                return nil
            }
        }
    }
}
