import UIKit
@preconcurrency import GoogleMobileAds

/// Implémentation réelle de InterstitialAdProviding. N'appelle jamais
/// MobileAds.shared.start() elle-même — RootView s'en charge une fois le
/// consentement résolu (Task 3).
///
/// API surface verified 2026-07-23 against the actually-resolved
/// GoogleMobileAds SDK headers (v13.7.0, pinned `from: 13.0.0` in
/// project.yml) in `GoogleMobileAds.xcframework/.../Headers/GADInterstitialAd.h`,
/// not transcribed from the plan's guessed sketch. `GADInterstitialAd` carries
/// `NS_SWIFT_NAME(InterstitialAd)` (so the class does de-prefix in Swift, same
/// as UMP's types in Task 3), and `GADRequest` carries `NS_SWIFT_NAME(Request)`.
/// `+ (void)loadWithAdUnitID:request:completionHandler:` (an
/// `(InterstitialAd?, Error?) -> Void` completion handler, the last
/// parameter) gets an automatically-synthesized `async throws` overload from
/// Swift's Clang importer — `static func load(with:request:) async throws ->
/// InterstitialAd` — confirmed from the header, no manual
/// `withCheckedThrowingContinuation` needed, matching the plan's guess.
///
/// `-presentFromRootViewController:` and `-canPresentFromRootViewController:error:`
/// are both annotated `NS_SWIFT_UI_ACTOR` in the header — the SDK itself
/// requires these to run on the main actor, which Swift 6 enforces at the
/// type level (this is why `show()` below is `@MainActor`, per
/// `InterstitialAdProviding`'s existing annotation). `+load(with:request:)`
/// carries no such annotation, so it is safe to call from a nonisolated
/// `async` context.
///
/// `GADInterstitialAd`/`InterstitialAd` is not marked `Sendable` in the SDK.
/// `InterstitialAdProviding.isReady` is a synchronous, nonisolated
/// requirement (no `@MainActor`, no `async`), so the whole type cannot be
/// isolated to `@MainActor` the way `UMPConsentProvider` was (Task 3) — that
/// would make `interstitial` MainActor-isolated and `isReady` would then be
/// unable to read it synchronously from a nonisolated context. Instead only
/// the UI-presenting members (`show()`, `topViewController()`) are
/// `@MainActor`, matching the SDK's own `NS_SWIFT_UI_ACTOR` boundary.
///
/// `interstitial` is read synchronously via `isReady` from a nonisolated
/// context (required by `InterstitialAdProviding`'s protocol shape), so it
/// can't be stored as `@MainActor`-isolated state — this is a genuine
/// Swift 6 constraint, not an oversight. Both WRITES to it (`load()`'s
/// assignment and `show()`'s nil-out) are pinned to the main actor via
/// `MainActor.run`/the method's own `@MainActor` isolation, so there is no
/// write/write race. A read via `isReady` racing a concurrent main-actor
/// write is still possible in principle — `nonisolated(unsafe)` gives the
/// compiler no enforcement here — but this codebase's only caller today
/// never invokes `load()` and `show()`/`isReady` concurrently. If a future
/// caller adds retry-on-failure or pre-fetch-next-ad logic that could
/// overlap those calls, revisit this with a lock (e.g.
/// `OSAllocatedUnfairLock`) rather than assuming the current single-caller
/// pattern still holds.
final class AdMobInterstitialProvider: NSObject, InterstitialAdProviding {
    private static let adUnitID = "ca-app-pub-3940256099942544/4411468910" // AdMob's public test interstitial ID — replace with the real unit ID once provisioned in the AdMob console (same TODO pattern as Task 1's GADApplicationIdentifier placeholder).

    nonisolated(unsafe) private var interstitial: InterstitialAd?

    var isReady: Bool { interstitial != nil }

    func load() async throws {
        let ad = try await InterstitialAd.load(with: Self.adUnitID, request: Request())
        await MainActor.run { self.interstitial = ad }
    }

    @MainActor
    func show() async -> Bool {
        guard let interstitial, let rootViewController = Self.topViewController() else { return false }
        interstitial.present(from: rootViewController)
        self.interstitial = nil
        return true
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first { $0.isKeyWindow }?.rootViewController
    }
}
