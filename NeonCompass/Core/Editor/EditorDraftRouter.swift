#if DEBUG
import Foundation

/// Écrit chaque brouillon dans le fichier, **toujours**, et le pousse au distant
/// quand un compte le permet.
///
/// **Ce n'est plus une alternative, et ça a coûté cinq captures le 2026-08-05.**
/// Le routeur choisissait l'un OU l'autre, et retombait sur le fichier si le
/// distant levait. Or `SupabaseEditorDraftStore.save` est `nonisolated` et se
/// contente d'un `Task { await enqueue(draft) }` : **il ne lève jamais**. Le
/// `catch` ne pouvait donc pas se déclencher, et la file — refusée par la RLS,
/// qui réserve `editor_drafts` aux comptes inscrits dans `editors` — mourait à
/// la fermeture de l'app. Cinq brouillons annoncés « en attente d'envoi »
/// n'existaient en réalité nulle part.
///
/// Le fichier porte donc la durabilité sans condition, et le distant n'est plus
/// qu'un envoi opportuniste par-dessus. Un `save` distant qui accepte sans
/// livrer ne peut plus rien perdre.
///
/// **Écrire des deux côtés est sans danger**, et ce fichier le disait déjà : les
/// deux chemins produisent le même objet, `pull-drafts` les matérialise
/// identiquement, et l'idempotence par `processedFrom` fait qu'un brouillon
/// passé par les deux ne crée pas deux entrées.
///
/// La décision distante se prend **à chaque écriture**, pas à la construction.
/// L'éditeur est bâti en valeur initiale d'un `@State`, bien avant qu'on sache
/// si quelqu'un est connecté ; figer le choix à ce moment-là condamnerait la
/// session entière au seul fichier, même après une connexion réussie.
final class EditorDraftRouter: EditorDraftStore {
    private let remote: EditorDraftStore
    private let local: EditorDraftStore
    private let isRemoteUsable: @Sendable () -> Bool

    init(
        remote: EditorDraftStore,
        local: EditorDraftStore,
        isRemoteUsable: @escaping @Sendable () -> Bool
    ) {
        self.remote = remote
        self.local = local
        self.isRemoteUsable = isRemoteUsable
    }

    func save(_ draft: EditorDraft) throws {
        // Le fichier D'ABORD et SANS CONDITION. C'est la seule écriture dont
        // l'échec compte : lui seul est synchrone et acquitté sur le disque
        // quand il rend la main. Le laisser lever est délibéré — une capture
        // qu'on ne peut pas persister doit être annoncée perdue, pas
        // enregistrée.
        try local.save(draft)

        guard isRemoteUsable() else { return }
        do {
            try remote.save(draft)
        } catch {
            // Opportuniste : le fichier a déjà la capture, un refus distant ne
            // coûte plus rien. On le journalise sans rendre d'erreur à
            // quelqu'un qui a les mains prises par une manette.
            print("EditorDraftRouter: le distant a refusé \(draft.id), le fichier l'a — \(error)")
        }
    }

    func waitForDelivery() async throws {
        guard isRemoteUsable() else { return }
        try await remote.waitForDelivery()
    }
}
#endif
