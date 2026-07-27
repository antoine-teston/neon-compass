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
    /// Résolu à l'appel, jamais à la construction. `Firestore.firestore()` plante
    /// d'une erreur fatale NON RATTRAPABLE si `FirebaseApp.configure()` n'a pas
    /// tourné (cf. `FirebaseAvailability`) — et cet entrepôt est construit en
    /// valeur initiale d'un `@State`, donc potentiellement avant toute
    /// configuration. `EditorModel` refuse par ailleurs de s'armer tant que le
    /// backend n'est pas disponible : ces méthodes ne sont donc jamais atteintes
    /// à vide.
    private var firestore: Firestore { Firestore.firestore() }

    func save(_ draft: EditorDraft) throws {
        try firestore.collection("editor_drafts").document(draft.id).setData(from: draft)
    }

    func waitForDelivery() async throws {
        try await firestore.waitForPendingWrites()
    }
}
#endif
