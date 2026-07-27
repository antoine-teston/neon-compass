@preconcurrency import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Efface la progression synchronisée puis le compte Firebase Auth.
///
/// L'ordre compte : une fois le compte supprimé, `request.auth` est nul et les
/// règles refusent tout accès à `profiles/{uid}/…`. Supprimer le compte en
/// premier laisserait donc la progression orpheline et **définitivement**
/// inaccessible — y compris à un administrateur, qui n'aurait plus l'uid.
final class FirebaseClientAccountDeletion: AccountDeleting {
    /// Résolus à l'appel, jamais à la construction : cette classe est bâtie en
    /// valeur initiale d'un `@State`, donc potentiellement avant
    /// `FirebaseApp.configure()`, et `Firestore.firestore()` plante alors d'une
    /// erreur fatale non rattrapable (cf. `FirebaseAvailability`).
    private var firestore: Firestore { Firestore.firestore() }
    private var auth: Auth { Auth.auth() }

    func deleteAccount(uid: String) async throws {
        let progression = firestore.collection("profiles").document(uid).collection("progression")
        let snapshot = try await progression.getDocuments()

        // Découpé à 500 : c'est le plafond d'opérations d'un batch Firestore, et
        // une progression complète peut le dépasser (un document par item
        // trouvé). Même correctif que `pushDocuments` côté CLI, où un batch
        // unique aurait échoué d'un bloc sur la fixture de 537 entrées.
        for chunk in snapshot.documents.chunked(into: 500) {
            let batch = firestore.batch()
            chunk.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
        }

        // Lève `requiresRecentLogin` si la session est ancienne — l'appelant le
        // remonte à l'utilisateur, qui répare en se reconnectant.
        try await auth.currentUser?.delete()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
