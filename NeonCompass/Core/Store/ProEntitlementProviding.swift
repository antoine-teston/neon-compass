import Foundation

/// Abstraction sur StoreKit 2 — seule source de vérité locale pour savoir si
/// cet utilisateur a acheté Pro (spec §"Pro" : "L'entitlement StoreKit signé
/// par Apple est la source de vérité locale"). N'est jamais adossée à un
/// appel serveur.
protocol ProEntitlementProviding: Sendable {
    /// Vérifie les entitlements StoreKit actuels (par ex. au lancement).
    func currentEntitlement() async -> Bool

    /// Déclenche l'achat Pro. Retourne si l'app est désormais entitled
    /// (false si l'utilisateur annule — ce n'est pas une erreur). N'exige
    /// jamais que l'appelant soit connecté.
    func purchase() async throws -> Bool

    /// Resynchronise les entitlements depuis Apple (exigence App Store
    /// Connect « Restore Purchases », spec table de risques "3.1.1 (IAP)").
    func restorePurchases() async throws -> Bool

    /// Mises à jour en direct au fil du flux `Transaction.updates` de
    /// StoreKit (par ex. un remboursement, ou un achat qui se termine après
    /// que l'app a été mise en arrière-plan pendant un Ask to Buy).
    var entitlementUpdates: AsyncStream<Bool> { get }
}
