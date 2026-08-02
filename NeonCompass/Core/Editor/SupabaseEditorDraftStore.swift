#if DEBUG
import Foundation
import Supabase

/// Écrit dans `editor_drafts`, table qu'aucun chemin de contenu de l'app ne lit
/// et que RLS réserve aux comptes inscrits dans `editors`.
///
/// **Ce store perd une propriété que Firestore offrait gratuitement, et il faut
/// le dire.** `setData(from:)` rendait la main dès l'écriture LOCALE : le SDK
/// persistait sur disque et rejouait la file au retour du réseau, ce qui rendait
/// la capture utilisable dans un sous-sol sans une ligne de code de notre part.
/// PostgREST n'a pas de file hors-ligne.
///
/// D'où la file ici, en mémoire : `save` empile et rend la main immédiatement —
/// la capture doit tenir en moins de trois secondes, réseau ou pas — et
/// `waitForDelivery` vide la file en attendant l'acquittement du serveur. C'est
/// exactement le contrat du protocole.
///
/// Ce qui reste en moins par rapport à Firestore : la file ne survit pas à la
/// fermeture de l'app. `EditorDraftRouter` retombe sur `FileEditorDraftStore`
/// quand le chemin distant n'est pas utilisable, et c'est lui qui porte la
/// durabilité — une capture de terrain ne se refait pas.
actor SupabaseEditorDraftStore: EditorDraftStore {
    private struct Row: Encodable {
        let id: String
        let authorUid: String
        let payload: EditorDraft

        enum CodingKeys: String, CodingKey {
            case id
            case authorUid = "author_uid"
            case payload
        }
    }

    private let client: SupabaseClient?
    private var pending: [EditorDraft] = []

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    nonisolated func save(_ draft: EditorDraft) throws {
        Task { await enqueue(draft) }
    }

    private func enqueue(_ draft: EditorDraft) {
        pending.append(draft)
    }

    func waitForDelivery() async throws {
        guard let client, let uid = client.auth.currentUser?.id.uuidString else {
            throw SupabaseAuthError.notConfigured
        }
        // Retirées de la file seulement APRÈS acquittement : une erreur les y
        // laisse, et le prochain appel les repropose. Vider d'abord perdrait la
        // capture précisément quand le réseau est mauvais.
        let batch = pending
        guard !batch.isEmpty else { return }
        let rows = batch.map { Row(id: $0.id, authorUid: uid, payload: $0) }
        try await client.from("editor_drafts").upsert(rows, onConflict: "id").execute()
        pending.removeFirst(batch.count)
    }
}
#endif
