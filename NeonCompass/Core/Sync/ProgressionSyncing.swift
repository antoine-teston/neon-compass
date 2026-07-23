import Foundation

enum ProgressionItemKind: String, Codable, Sendable {
    case poi, trophy
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
