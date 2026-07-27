#if DEBUG
import FirebaseFirestore
import Foundation

/// Écrit dans `editor_drafts`, collection qu'aucun chemin de contenu de l'app ne
/// lit et que les Security Rules réservent à un seul UID.
///
/// `setData(from:)` rend la main dès l'écriture locale : le SDK persiste sur
/// disque et rejoue la file au retour du réseau. C'est ce qui rend la capture
/// utilisable dans un sous-sol sans une ligne de code de notre part — et ce qui
/// fait qu'une session de trois heures ne tient jamais sur le seul appareil.
final class FirestoreEditorDraftStore: EditorDraftStore {
    /// `nonisolated(unsafe)` comme `FirestoreContributionRepository` : les types
    /// du SDK ne sont pas `Sendable`, alors qu'ils sont thread-safe par contrat.
    nonisolated(unsafe) private let firestore: Firestore
    nonisolated(unsafe) private let collection: CollectionReference

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
        collection = firestore.collection("editor_drafts")
    }

    func save(_ draft: EditorDraft) throws {
        try collection.document(draft.id).setData(from: draft)
    }

    func waitForDelivery() async throws {
        try await firestore.waitForPendingWrites()
    }
}
#endif
