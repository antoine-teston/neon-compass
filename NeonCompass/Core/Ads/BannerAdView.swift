import SwiftUI
import UIKit
@preconcurrency import GoogleMobileAds

/// Bannière adaptative — jamais sur MapScreen (Global Constraints de ce
/// plan). N'appelle jamais MobileAds.shared.start() elle-même.
///
/// API surface verified 2026-07-23 against the actually-resolved
/// GoogleMobileAds SDK headers (v13.7.0, same xcframework Task 4 inspected)
/// in `GADBannerView.h` / `GADAdSize.h`, not transcribed from the plan's
/// guessed sketch:
/// - `GADBannerView` carries `NS_SWIFT_NAME(BannerView)` — confirmed.
/// - `GADRequest` carries `NS_SWIFT_NAME(Request)`, no `NS_UNAVAILABLE` on a
///   plain `init` — `Request()` compiles, same finding as Task 4's
///   `AdMobInterstitialProvider`.
/// - `-loadRequest:` has no `NS_SWIFT_NAME` override, so the Clang importer
///   drops the `Request` suffix (it matches the parameter type name),
///   producing `func load(_ request: Request?)` in Swift — this is why
///   `banner.load(Request())` below compiles; it is NOT the completion-based
///   `load(with:)` used by `AdMobInterstitialProvider`, a different method.
/// - The plan's sketch called `currentOrientationAnchoredAdaptiveBanner(width:)`
///   (`GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth`), but that
///   C function is marked `GAD_DEPRECATED_MSG_REPLACEMENT_ATTRIBUTE` in this
///   resolved version, replaced by
///   `GADLargeAnchoredAdaptiveBannerAdSizeWithWidth` /
///   `largeAnchoredAdaptiveBanner(width:)`. Used the non-deprecated call
///   here to avoid a build warning; behavior is equivalent (still orientation-
///   aware, still returns the standard ~50-150pt anchored adaptive height).
/// - `UIViewRepresentable` itself is declared
///   `@preconcurrency @MainActor public protocol UIViewRepresentable` in
///   SwiftUI's resolved swiftinterface (confirmed via
///   `SwiftUI.swiftmodule/*.swiftinterface`), so conforming
///   `makeUIView`/`updateUIView` are already MainActor-isolated by the
///   protocol itself — no extra `@MainActor` annotation is needed here,
///   unlike `AdMobInterstitialProvider`'s manually-isolated members (that
///   type doesn't conform to a MainActor-isolated protocol).
///
/// Sizing note: the adaptive width MUST come from SwiftUI's own layout
/// (`GeometryReader`), not `UIScreen.main.bounds.width` — the latter is the
/// full physical screen width, which is wrong wherever the banner's
/// container is narrower than the screen (e.g. iPad's `.sidebarAdaptable`
/// tab layout, where the content column sizing `FeedListView`/
/// `CheatsListView`/`GuidesListView` — and therefore this banner — is
/// narrower than the full screen). `BannerAdView` is therefore a thin
/// SwiftUI `View` wrapping a private `UIViewRepresentable` that receives the
/// real container width via `GeometryReader`.
struct BannerAdView: View {
    var adUnitID: String = "ca-app-pub-3940256099942544/2934735716" // AdMob's public test adaptive-banner ID — replace once provisioned.

    var body: some View {
        GeometryReader { geometry in
            BannerAdRepresentable(adUnitID: adUnitID, width: geometry.size.width)
        }
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: largeAnchoredAdaptiveBanner(width: width > 0 ? width : UIScreen.main.bounds.width))
        banner.adUnitID = adUnitID
        banner.rootViewController = AdPresentationContext.topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // Re-adapt when the available width actually changes (rotation,
        // iPad Split View resize, sidebar collapse/expand) — this also
        // closes a second, related gap the same review flagged: the
        // previous updateUIView was a no-op, so the banner never
        // re-adapted after creation.
        guard width > 0, uiView.adSize.size.width != width else { return }
        uiView.adSize = largeAnchoredAdaptiveBanner(width: width)
        uiView.load(Request())
    }
}
