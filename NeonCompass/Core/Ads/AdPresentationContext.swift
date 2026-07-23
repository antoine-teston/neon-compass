import UIKit

/// Shared UIWindowScene/root-view-controller lookup for the ad-presenting
/// SDK wrappers in this folder (UMPConsentProvider, AdMobInterstitialProvider,
/// BannerAdView) — extracted after the third byte-identical occurrence of
/// this lookup, per this codebase's convention. `@MainActor` because
/// `UIApplication.shared`/`UIWindowScene`/`UIWindow` access must happen on
/// the main thread, matching every caller's own isolation (UMPConsentProvider
/// is whole-type @MainActor; AdMobInterstitialProvider/BannerAdView call
/// this only from their own @MainActor-isolated members).
@MainActor
enum AdPresentationContext {
    /// Prefers the foreground-active scene — `connectedScenes` is an
    /// unordered Set, so a plain `.first` picks an arbitrary scene, which
    /// is nondeterministic under iPad multi-window/Slide Over.
    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return activeScene?.windows.first { $0.isKeyWindow }
    }

    static func topViewController() -> UIViewController? {
        keyWindow?.rootViewController
    }
}
