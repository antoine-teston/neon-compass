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
/// Sizing note: `BannerAdView` self-sizes to the REAL adaptive-banner height
/// Google computes for its own available width, rather than a caller-guessed
/// fixed height — a caller wrapping this in a fixed-height container (as the
/// first UI-polish round did) risks clipping or leaving dead space whenever
/// the actual ad format is taller/shorter than the guess. Width is measured
/// via a `.background`-attached `GeometryReader` rather than making this
/// view's own body a `GeometryReader` — the latter greedily expands to fill
/// all available height in its container (a well-known SwiftUI pitfall),
/// which is exactly wrong for a view meant to report its OWN natural height
/// back to the caller.
///
/// Verified-by-running correction to the original plan sketch: the
/// conditional content MUST have a real `else` branch (`Color.clear` below),
/// not just `if measuredWidth > 0 { ... }` with no `else`. Empirically
/// confirmed on-device (iOS 26.5 Simulator) that when a `Group`'s ViewBuilder
/// content resolves to the "false" case of an `if` with no `else`, SwiftUI
/// never lays out or composites a `.background(GeometryReader { ... })`
/// attached to that group — the `GeometryReader`'s closure is never even
/// invoked, so its `onAppear`/`onChange` never fire and `measuredWidth` can
/// never leave its initial 0, permanently hiding the ad. Isolated with a
/// minimal repro (`Group { if x { Color.blue } }` vs. the same with
/// `else { Color.clear }`) — only the `else` version's `GeometryReader`
/// closure ever ran. Giving the `Group` a real view in both branches sidesteps
/// this: the `.background` now always has concrete content to size against,
/// so the `GeometryReader` reliably measures width from the first render.
struct BannerAdView: View {
    var adUnitID: String = "ca-app-pub-3940256099942544/2934735716" // AdMob's public test adaptive-banner ID — replace once provisioned.
    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        Group {
            if measuredWidth > 0 {
                BannerAdRepresentable(adUnitID: adUnitID, width: measuredWidth)
                    .frame(height: largeAnchoredAdaptiveBanner(width: measuredWidth).size.height)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        if newValue > 0 { measuredWidth = newValue }
                    }
            }
        )
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
