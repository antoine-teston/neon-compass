import StoreKit

/// Implémentation réelle de ProEntitlementProviding. Ne référence jamais
/// Firestore/FirebaseAuth — ce fichier ne fait que parler à StoreKit,
/// l'appelant (ProEntitlementModel) décide s'il faut aussi notifier le
/// serveur (Task 5, App Store Server Notifications V2, pas ici).
///
/// API surface verified 2026-07-23 via Apple's official documentation
/// (partially — the doc site's rendered body wasn't fetchable through
/// available tooling, only page titles were) cross-checked against multiple
/// independent third-party StoreKit 2 write-ups (swiftwithmajid.com,
/// bleepingswift.com) and Apple Developer Forums threads, all agreeing on
/// the same shapes:
/// - `Product.products(for:) async throws -> [Product]` is unchanged since
///   iOS 15; `Product` is a `Sendable` value type.
/// - `Product.purchase() async throws -> Product.PurchaseResult` still has
///   exactly three cases confirmed by every source: `.success(let
///   verification)`, `.userCancelled`, `.pending` (plus `@unknown default`
///   for forward compatibility) — matches the plan's sketch exactly.
/// - `VerificationResult<Transaction>` still has `.verified(Transaction)` /
///   `.unverified(Transaction, VerificationError)` — the classic switch
///   pattern the plan sketched is still valid. (Newer code also has sugar —
///   a throwing `payloadValue` property — but the explicit switch is kept
///   here since it matches this codebase's existing explicit-switch style
///   in `Core/Ads/AdMobInterstitialProvider.swift`.)
/// - `Transaction.currentEntitlements` and `Transaction.updates` are both
///   confirmed as `AsyncSequence`s of `VerificationResult<Transaction>`,
///   unchanged since iOS 15. (`Transaction.currentEntitlement(for:)`,
///   singular, is a *different*, now-deprecated API — not used here.)
/// - `Transaction.finish() async` and `AppStore.sync() async throws` are
///   both unchanged.
///
/// One material addition since iOS 15 that the plan's sketch predates:
/// iOS 18.2 added `Product.purchase(confirmIn:options:)`, an overload that
/// takes a `UIViewController` (or `NSWindow` on macOS) so the system can
/// anchor the payment sheet to a specific window/scene on multi-window
/// devices (iPad Stage Manager, Vision Pro). It does NOT deprecate or
/// replace plain `purchase()` — sources agree the argument-less overload
/// still works everywhere. Deliberately NOT adopted here: it would require
/// this file to import UIKit and resolve a presenting view controller
/// (mirroring `AdPresentationContext.topViewController()` in
/// `Core/Ads/AdMobInterstitialProvider.swift`), which conflicts with this
/// file's one job — "ne fait que parler à StoreKit" — and with keeping
/// `ProEntitlementProviding` UI-agnostic so `ProEntitlementModel` (Task 2)
/// can call `purchase()` without threading a view controller through it.
/// Revisit if Neon Compass ever supports true iPad multi-window and users
/// report the sheet anchoring to the wrong window.
///
/// Isolation: confirmed directly against the resolved iOS 26 SDK's
/// `StoreKit.swiftinterface` (not a secondary source) —
/// `Product.purchase(options:)` IS `@MainActor`-isolated in the shipping
/// SDK, unlike what an earlier pass of this comment claimed. This does not
/// require `StoreKitProProvider` itself to be `@MainActor`, unlike
/// `UMPConsentProvider`: `purchase()` here is `async`, and Swift's
/// concurrency runtime automatically inserts an actor hop at the call site
/// for an `async` `@MainActor` function called from any context — no
/// physical-main-thread enforcement is needed the way UMP/AdMob's
/// synchronous, `NS_SWIFT_UI_ACTOR`-annotated ObjC methods require. Only
/// `purchase()` carries this annotation — `Product.products(for:)`,
/// `AppStore.sync()`, and the `Transaction` async sequences are confirmed
/// unisolated in the same `.swiftinterface`. This type therefore needs no
/// `@MainActor` isolation and no stored SDK handle needing
/// `nonisolated(unsafe)` — it holds no mutable instance state at all (only
/// the `static let` product ID), so it is trivially `Sendable` without
/// `@unchecked`.
final class StoreKitProProvider: ProEntitlementProviding, Sendable {
    static let proProductID = "co.antoineteston.neoncompass.pro"

    func currentEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.proProductID {
                return true
            }
        }
        return false
    }

    func purchase() async throws -> Bool {
        let products = try await Product.products(for: [Self.proProductID])
        guard let product = products.first else {
            throw ProEntitlementError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw ProEntitlementError.unverifiedTransaction
            }
            await transaction.finish()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restorePurchases() async throws -> Bool {
        try await AppStore.sync()
        return await currentEntitlement()
    }

    var entitlementUpdates: AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result, transaction.productID == Self.proProductID else { continue }
                    await transaction.finish()
                    continuation.yield(await currentEntitlement())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum ProEntitlementError: Error {
    case productNotFound
    case unverifiedTransaction
}
