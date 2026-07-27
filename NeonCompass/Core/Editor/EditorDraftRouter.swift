#if DEBUG
import Foundation

/// Envoie chaque brouillon là où il peut réellement aller : Firestore quand un
/// compte existe, le fichier local sinon.
///
/// La décision se prend **à chaque écriture**, pas à la construction. L'éditeur
/// est bâti en valeur initiale d'un `@State`, bien avant qu'on sache si
/// quelqu'un est connecté ; figer le choix à ce moment-là condamnerait la
/// session entière au repli, même après une connexion réussie.
///
/// Les deux chemins produisent le même objet : `pull-drafts` les matérialise
/// identiquement, et l'idempotence par `processedFrom` fait qu'un brouillon
/// passé par les deux ne créerait pas deux entrées.
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
        guard isRemoteUsable() else {
            try local.save(draft)
            return
        }
        do {
            try remote.save(draft)
        } catch {
            // Un refus distant ne doit jamais perdre une capture : on retombe
            // sur le fichier plutôt que de rendre une erreur à quelqu'un qui a
            // les mains prises par une manette.
            print("EditorDraftRouter: Firestore a refusé \(draft.id), repli sur le fichier — \(error)")
            try local.save(draft)
        }
    }

    func waitForDelivery() async throws {
        guard isRemoteUsable() else { return }
        try await remote.waitForDelivery()
    }
}
#endif
