import Foundation

/// Une seule sorte depuis le retrait des trophées (2026-08-19).
///
/// L'énumération subsiste plutôt que d'être aplatie en `String` : c'est elle qui
/// fait que `fetchAll` écarte les lignes `kind = 'trophy'` laissées en base par
/// les versions précédentes, au lieu de les décoder puis de les ignorer plus
/// loin. La contrainte `check (kind in ('poi','trophy'))` reste en base — ces
/// lignes restent valides, on cesse simplement d'en écrire.
enum ProgressionItemKind: String, Codable, Sendable {
    case poi
}

struct ProgressionSyncItem: Sendable {
    let itemID: String
    let kind: ProgressionItemKind
    let found: Bool
    let updatedAt: Date
}

/// Abstraction over the Firestore-backed progression mirror. Cloud sync is
/// Pro + signed-in only (spec: "nécessite le compte") — every caller must
/// check both `ProEntitlementModel.isProEntitled` and `AuthModel.userID`
/// before calling this at all; this protocol itself has no opinion on
/// entitlement or auth state, it just moves data once asked to.
protocol ProgressionSyncing: Sendable {
    func upload(itemID: String, kind: ProgressionItemKind, found: Bool, updatedAt: Date) async
    func fetchAll(uid: String) async -> [ProgressionSyncItem]
}
