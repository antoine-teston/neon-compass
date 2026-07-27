#if DEBUG
import Foundation

/// Entrepôt de brouillons. Firebase reste derrière ce protocole (CLAUDE.md) :
/// `EditorModel` ne connaît que lui, et les tests lui substituent un double en
/// mémoire — aucun test n'a besoin de Firestore.
protocol EditorDraftStore: Sendable {
    /// Persiste localement et rend la main immédiatement — l'envoi réseau est
    /// asynchrone et peut n'arriver que bien plus tard. Ne jamais attendre ici :
    /// la capture doit tenir en moins de trois secondes, réseau ou pas.
    func save(_ draft: EditorDraft) throws

    /// Rend la main quand toutes les écritures en attente ont été acquittées par
    /// le serveur. Ne rend jamais la main tant qu'on est hors-ligne — c'est
    /// voulu, c'est exactement ce que le bandeau doit annoncer.
    func waitForDelivery() async throws
}
#endif
