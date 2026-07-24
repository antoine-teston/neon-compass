# UI/UX Polish Round 2 (ad banner sizing, Map cover-fit + unified top row, tab label) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four follow-up issues raised after the first UI/UX polish round shipped: the ad banner bubble doesn't match the real adaptive-banner ad size, the Map's "fit the whole map, letterboxed" initial view reads as "the map doesn't move/zoom" and doesn't fill the screen, the Map's search field doesn't fill the space between the favorites bubble and the filter toggle, and the bottom tab bar's "Progression" label wraps to two lines.

**Architecture:** Task 1 makes `BannerAdView` self-size to the real AdMob-computed adaptive height instead of a hardcoded guess. Task 2 (highest risk, touches the same UIKit engine as the previous round's Map fix) adds a second pure, testable zoom-scale function (`coverZoomScale`, "cover" instead of "contain") plus a properly generalized centered-offset function that correctly handles a cropped (larger-than-viewport) axis — the previous round's centering math only handled the "content fits inside the viewport" case correctly. Task 3 restructures the Map's top overlay into one unified full-width row (favorites/route buttons, flexible search field, filter toggle) so the search field can actually fill the gap between the two ends. Task 4 is a one-line label fix.

**Tech Stack:** SwiftUI, UIKit (`CATiledLayer`/`UIScrollView`, confined to the existing `TiledMapView.swift`), Swift Testing.

## Global Constraints

- **iPad-first-class (CLAUDE.md):** Task 2's cover-fit change must not regress the previous round's iPad side-panel zoom/pan-preservation fix (the `hasPerformedInitialFit` guard and its `else` branch stay untouched — only the `if !hasPerformedInitialFit` branch's math changes). Task 3's unified row must work in both `sizeClass == .compact` and regular/`sidebarAdaptable` (already true today since `MapFilterControls` doesn't currently branch on size class — this plan doesn't change that).
- **Localizable.xcstrings rule:** no new user-facing strings are introduced by this plan — verify this holds for all four tasks.
- **Swift 6 strict concurrency, SwiftUI only, UIKit confined to `TiledMapView.swift`** (CLAUDE.md) — unchanged by this plan.
- **Tests: Swift Testing** (CLAUDE.md) for the new pure functions in Task 2.
- **No UI test target exists** in this repo (confirmed in `project.yml`) — every visual fix must still get a real Simulator check by the implementer, reported honestly per what could/couldn't be reached without tap automation.

## File Structure

- Modify: `NeonCompass/Core/Ads/BannerAdView.swift` — Task 1 (self-sizing to the real adaptive height).
- Modify: `NeonCompass/Features/Feed/FeedListView.swift` — Task 1 (drop the hardcoded banner height, adjust reserved scroll clearance).
- Modify: `NeonCompass/Features/Cheats/CheatsListView.swift` — Task 1 (same).
- Modify: `NeonCompass/Core/Map/MapGeometry.swift` — Task 2 (new `coverZoomScale`, `centeredContentOffset` pure functions).
- Modify: `NeonCompass/Core/Map/TiledMapView.swift` — Task 2 (initial fit now uses cover-scale + the new centered-offset function).
- Modify: `NeonCompassTests/Map/MapGeometryTests.swift` — Task 2 (tests for the two new functions).
- Modify: `NeonCompass/Features/Map/MapFilterControls.swift` — Task 3 (owns the favorites/route buttons now, unified full-width top row).
- Modify: `NeonCompass/Features/Map/MapScreen.swift` — Task 3 (removes the now-redundant favorites/route button block from `mapCanvas`, passes two new bindings into `MapFilterControls`, changes `ZStack` alignment from `.topTrailing` to `.top`).
- Modify: `NeonCompass/App/CompactTabBar.swift` — Task 4 (tab label no longer wraps).

## Task 1: Ad banner self-sizes to the real adaptive-banner height

**Files:**
- Modify: `NeonCompass/Core/Ads/BannerAdView.swift`
- Modify: `NeonCompass/Features/Feed/FeedListView.swift`
- Modify: `NeonCompass/Features/Cheats/CheatsListView.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `BannerAdView` no longer needs an external `.frame(height:)` — it sizes itself to whatever `largeAnchoredAdaptiveBanner(width:)` actually reports for its real available width. `FeedListView`/`CheatsListView`'s `adBanner` computed properties drop their `.frame(height: 50)` on `BannerAdView()` accordingly.

**Context:** The previous round wrapped `BannerAdView()` in a glass bubble with a hardcoded `.frame(height: 50)`. `BannerAdView` internally calls `largeAnchoredAdaptiveBanner(width:)` (a real AdMob API — Google's "large" adaptive banner format, which computes its *actual* height from the available width and can be taller than 50pt on many devices), so the bubble's fixed 50pt height doesn't necessarily match what the ad actually renders at — "the new ad" doesn't fit the bubble. The fix: measure `BannerAdView`'s own available width (via a `.background`-attached `GeometryReader`, which reports size without forcing the view to greedily expand the way a plain top-level `GeometryReader` would), compute the real ad size from that width using the *same* `largeAnchoredAdaptiveBanner` call already used internally, and size the view to match exactly — so the glass bubble around it is always the right shape for whatever ad format is actually loaded, current or future.

- [ ] **Step 1: Rewrite `BannerAdView.swift` to self-size**

Replace the `BannerAdView` struct (keep `BannerAdRepresentable` exactly as-is — it's already correct and reviewed) with:

```swift
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
struct BannerAdView: View {
    var adUnitID: String = "ca-app-pub-3940256099942544/2934735716" // AdMob's public test adaptive-banner ID — replace once provisioned.
    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        Group {
            if measuredWidth > 0 {
                BannerAdRepresentable(adUnitID: adUnitID, width: measuredWidth)
                    .frame(height: largeAnchoredAdaptiveBanner(width: measuredWidth).size.height)
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
```

- [ ] **Step 2: Update `FeedListView.swift`'s `adBanner` and clearance**

In `NeonCompass/Features/Feed/FeedListView.swift`, change:

```swift
    private var bannerClearance: CGFloat {
        (sizeClass == .compact ? NCLayout.compactTabBarClearance : 0) + 74
    }

    private var adBanner: some View {
        BannerAdView()
            .frame(height: 50)
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
    }
```
to:

```swift
    /// 110pt covers the tallest realistic `largeAnchoredAdaptiveBanner`
    /// result on a phone-width screen plus the bubble's own padding — the
    /// exact ad height is only known at runtime (it depends on device
    /// width), so this reserved-space constant is a deliberately
    /// conservative upper-bound estimate, not a measurement.
    private var bannerClearance: CGFloat {
        (sizeClass == .compact ? NCLayout.compactTabBarClearance : 0) + 110
    }

    private var adBanner: some View {
        BannerAdView()
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
    }
```
(Every other part of `FeedListView.swift` is unchanged — only these two properties.)

- [ ] **Step 3: Update `CheatsListView.swift`'s `adBanner` and clearance identically**

Apply the exact same two-property change (`bannerClearance` +110 instead of +74 with the same doc comment, `adBanner` drops `.frame(height: 50)`) to `NeonCompass/Features/Cheats/CheatsListView.swift`.

- [ ] **Step 4: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator, open Feed and Cheats as a non-Pro user, and confirm the ad banner's glass bubble now hugs the actual ad content's real height (no visible clipping, no obviously oversized empty bubble) and that scrolled content never sits behind it. Report exactly what was observed.

- [ ] **Step 5: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass (no logic touched, only view sizing).

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Core/Ads/BannerAdView.swift NeonCompass/Features/Feed/FeedListView.swift NeonCompass/Features/Cheats/CheatsListView.swift
git commit -m "fix: size the ad banner bubble to the real adaptive-banner height instead of a hardcoded guess"
```

## Task 2: Map — initial view fills the whole screen (cover-fit) with real pan/zoom room

**Files:**
- Modify: `NeonCompass/Core/Map/MapGeometry.swift`
- Modify: `NeonCompass/Core/Map/TiledMapView.swift`
- Modify: `NeonCompassTests/Map/MapGeometryTests.swift`

**Interfaces:**
- Produces: `MapGeometry.coverZoomScale(contentSize:in:) -> CGFloat` (mirrors `fitZoomScale` but picks the *larger* of the two axis ratios — "cover" instead of "contain" — so the map fills the viewport edge-to-edge, cropping the excess on one axis, instead of shrinking to show the whole map with letterboxing on both). `MapGeometry.centeredContentOffset(contentSize:zoomScale:in:) -> CGPoint` (a properly generalized centering formula — see Context below for why the previous round's approach silently only worked for the "content fits inside the viewport" case).
- Consumes: `MapGeometry.fitZoomScale`/`centeringInsets` (unchanged, from the previous round) — `minimumZoomScale` still uses the "contain" scale so a user can always pinch out to see the entire map; only the *initial* displayed zoom level changes to "cover".

**Context — why the previous fix still read as "can't move/zoom the map":** the previous round's `fitZoomScale` (using `min` of the two axis ratios — "contain") correctly showed the ENTIRE map on screen at the initial zoom level, letterboxed on whichever axis had slack. But that means: at that exact zoom level, there is *nothing more to pan into* (the whole map is already visible) and *nothing more to zoom out to* (you're already at `minimumZoomScale`) — from the user's perspective this reads as "the map doesn't move" even though nothing is technically broken. A real map viewer should fill the screen from the first frame (matching "il faut propager au full screen") and have genuine pannable/zoomable room immediately. The fix: use the *cover* scale (`max` of the two ratios) for the map's initial `zoomScale` instead, cropping the excess on one axis — while keeping `minimumZoomScale` at the *contain* scale, so the user can still pinch all the way out to see the whole map if they want.

This surfaces a second, previously-latent bug: the old `contentOffset = CGPoint(x: -insets.left, y: -insets.top)` formula is only correct when BOTH axes fit inside the viewport (the "contain" case, where `centeringInsets` never clamps to 0) — under "contain" fit this happened to always be true, so the bug never manifested. Under "cover" fit, exactly one axis is *cropped* (scaled content exceeds the viewport on that axis), and `centeringInsets` correctly clamps that axis's inset to 0 — but the old offset formula (`-insets.left`/`-insets.top`, which is 0 when the inset is 0) then leaves the crop pinned to the top/left edge instead of centering it. `centeredContentOffset` fixes this by computing the offset directly from `(scaledSize - bounds) / 2` per axis, which is correct in both the "fits" case (negative offset, matches the old formula exactly) and the "cropped" case (positive offset, centers the crop) — verified with concrete numbers in Step 1's tests.

- [ ] **Step 1: Write the failing tests for the two new pure functions**

Add to `NeonCompassTests/Map/MapGeometryTests.swift` (append inside the existing `struct MapGeometryTests`, after the existing centering tests):

```swift
    @Test func coverZoomScaleGrowsToFillTheLargerDimension() {
        // contentSize 2048x2048, bounds 390x844 (iPhone-shaped) — height is
        // the binding constraint this time (opposite of fitZoomScale, which
        // picks width): 844/2048 > 390/2048.
        let scale = MapGeometry.coverZoomScale(contentSize: CGSize(width: 2048, height: 2048), in: CGSize(width: 390, height: 844))
        #expect(abs(scale - 844.0 / 2048.0) < 0.0001)
    }

    @Test func coverZoomScaleNeverUpscalesPastOne() {
        let scale = MapGeometry.coverZoomScale(contentSize: CGSize(width: 100, height: 100), in: CGSize(width: 390, height: 844))
        #expect(scale == 1)
    }

    @Test func coverZoomScaleIsOneForDegenerateInput() {
        #expect(MapGeometry.coverZoomScale(contentSize: .zero, in: CGSize(width: 390, height: 844)) == 1)
        #expect(MapGeometry.coverZoomScale(contentSize: CGSize(width: 2048, height: 2048), in: .zero) == 1)
    }

    @Test func centeredContentOffsetIsNegativeWhenContentFitsInsideTheViewport() {
        // Scaled content 200x200 inside a 300x400 viewport — matches the
        // negative, inset-driven offset a "contain" fit produces.
        let offset = MapGeometry.centeredContentOffset(
            contentSize: CGSize(width: 200, height: 200),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(offset == CGPoint(x: -50, y: -100))
    }

    @Test func centeredContentOffsetIsPositiveWhenContentIsCroppedByTheViewport() {
        // Scaled content 500x500 exceeds both axes of a 300x400 viewport —
        // must be a POSITIVE offset that centers the crop, not zero.
        let offset = MapGeometry.centeredContentOffset(
            contentSize: CGSize(width: 500, height: 500),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(offset == CGPoint(x: 100, y: 50))
    }

    @Test func centeredContentOffsetForARealCoverFitScenario() {
        // The exact cover-fit scenario from coverZoomScaleGrowsToFillTheLargerDimension:
        // content 2048x2048 at scale 844/2048 -> scaled 844x844 exactly.
        // Width (844) exceeds the 390pt viewport (cropped, centered positive
        // offset); height (844) matches the 844pt viewport exactly (zero
        // offset, zero crop).
        let scale = 844.0 / 2048.0
        let offset = MapGeometry.centeredContentOffset(
            contentSize: CGSize(width: 2048, height: 2048),
            zoomScale: scale,
            in: CGSize(width: 390, height: 844)
        )
        #expect(abs(offset.x - 227) < 0.01)
        #expect(abs(offset.y - 0) < 0.01)
    }
```

- [ ] **Step 2: Run the tests to confirm they fail to compile**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/MapGeometryTests`
Expected: build failure — `MapGeometry.coverZoomScale`/`centeredContentOffset` not found.

- [ ] **Step 3: Add the two new pure functions to `MapGeometry.swift`**

Add these two functions inside the existing `enum MapGeometry` (alongside `fitZoomScale`/`centeringInsets`, which stay completely unchanged):

```swift
    /// The zoom scale at which `contentSize` fills `bounds` completely on
    /// BOTH axes (cropping the excess on whichever axis has slack), rather
    /// than showing all of `contentSize` letterboxed — the "cover" analog of
    /// `fitZoomScale`'s "contain". Never upscaled past 1 for the same reason
    /// as `fitZoomScale`; returns 1 for degenerate (zero-sized) input.
    static func coverZoomScale(contentSize: CGSize, in bounds: CGSize) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        let scale = max(bounds.width / contentSize.width, bounds.height / contentSize.height)
        return min(scale, 1)
    }

    /// The `contentOffset` that centers content of `contentSize` scaled by
    /// `zoomScale` within `bounds`, on both axes independently — unlike
    /// `centeringInsets` (which only produces a valid *inset* for an axis
    /// where the scaled content is smaller than `bounds`, clamping to 0
    /// otherwise), this also correctly centers an axis where the scaled
    /// content EXCEEDS `bounds` (a "cover" crop) by returning a positive
    /// offset for that axis instead of leaving it pinned at 0.
    static func centeredContentOffset(contentSize: CGSize, zoomScale: CGFloat, in bounds: CGSize) -> CGPoint {
        let scaledWidth = contentSize.width * zoomScale
        let scaledHeight = contentSize.height * zoomScale
        return CGPoint(x: (scaledWidth - bounds.width) / 2, y: (scaledHeight - bounds.height) / 2)
    }
```

- [ ] **Step 4: Run the tests again — should pass now**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/MapGeometryTests`
Expected: all pass, including the 6 new tests.

- [ ] **Step 5: Wire the cover-fit initial view into `TiledMapView.swift`**

In `NeonCompass/Core/Map/TiledMapView.swift`, change only the `if !hasPerformedInitialFit` branch of `FitToBoundsScrollView.layoutSubviews()` — the `else` branch (which preserves the user's zoom/pan across later bounds changes, e.g. the iPad side-panel fix from the previous round) stays completely untouched:

```swift
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastFittedBoundsSize,
              bounds.width > 0, bounds.height > 0,
              contentNativeSize != .zero else { return }
        lastFittedBoundsSize = bounds.size

        // minimumZoomScale always allows pinching all the way out to see the
        // ENTIRE map (aspect-fit / "contain") — the initial view below fills
        // the screen edge-to-edge instead, but the user can still zoom out
        // to this contain-scale at any time.
        let containScale = MapGeometry.fitZoomScale(contentSize: contentNativeSize, in: bounds.size)
        minimumZoomScale = containScale

        if !hasPerformedInitialFit {
            hasPerformedInitialFit = true
            // The initial view fills the whole screen edge-to-edge ("cover"),
            // cropping the excess on whichever axis has slack, instead of
            // shrinking to show the entire map letterboxed — a "contain"
            // start left nothing new to reveal by panning and nothing to
            // zoom out to (already at the minimum), which read as "the map
            // doesn't move." This gives real, immediate pan/zoom room from
            // the first frame.
            let coverScale = MapGeometry.coverZoomScale(contentSize: contentNativeSize, in: bounds.size)
            zoomScale = coverScale
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: coverScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            contentOffset = MapGeometry.centeredContentOffset(contentSize: contentNativeSize, zoomScale: coverScale, in: bounds.size)
        } else {
            // Bounds changed after the user may have already zoomed/panned
            // (e.g. iPad's POI detail side panel resizing the map's column,
            // or a rotation) — never yank zoom back to a fitted scale here,
            // only keep the zoom range valid and re-center the inset margin
            // so any now-smaller-than-viewport content stays centered
            // without discarding the user's current zoomScale/contentOffset.
            zoomScale = max(zoomScale, minimumZoomScale)
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: zoomScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        }
    }
```
(Every other part of `TiledMapView.swift` — `TilePyramid`, `TiledCanvasView`, `TiledMapRepresentable`, `Coordinator` — is completely unchanged.)

- [ ] **Step 6: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator, open the Map tab, and confirm: the map now fills the entire screen from the first frame (no black letterboxing bars visible at the initial zoom level), panning immediately reveals more of the map on the cropped axis, and pinching in/out both do something meaningful (in: zooms toward native resolution; out: reveals the letterboxed whole-map view, down to `minimumZoomScale`). Test on both an iPhone-shaped and iPad-shaped destination per the iPad-first-class constraint, and re-confirm the previous round's fix still holds: opening a POI detail on iPad (which resizes the map's column) must not reset the user's zoom/pan.

- [ ] **Step 7: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass, including the 6 new `MapGeometryTests` additions (should be 108 total — 102 + 6).

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Core/Map/MapGeometry.swift NeonCompass/Core/Map/TiledMapView.swift NeonCompassTests/Map/MapGeometryTests.swift
git commit -m "fix: map's initial view fills the whole screen (cover-fit) instead of showing the whole map letterboxed, with a correctly centered crop"
```

## Task 3: Map — unify the top controls into one row so the search field fills the gap

**Files:**
- Modify: `NeonCompass/Features/Map/MapFilterControls.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`

**Interfaces:**
- Produces: `MapFilterControls` now takes two additional `@Binding var showPersonalPinList: Bool` / `@Binding var showRoutePlanner: Bool` parameters and owns the favorites/route-planner buttons directly (previously defined inline in `MapScreen.mapCanvas`).
- Consumes: nothing from Task 2 (independent files — `MapFilterControls.swift`/`MapScreen.swift` here vs. `MapGeometry.swift`/`TiledMapView.swift` there).

**Context:** Today the favorites/route buttons (`MapScreen.mapCanvas`, a `VStack` anchored `.topLeading`) and `MapFilterControls` (anchored `.topTrailing` in a *separate*, outer `ZStack`) are two independent view trees with no shared layout — the search field's width is a fixed 200pt entirely inside the trailing cluster, nowhere near the leading favorites bubble. To make the search field genuinely "fill the space between the favorites bubble and the categories toggle," they need to be siblings in ONE `HStack` — this moves the favorites/route buttons into `MapFilterControls` (which becomes the sole owner of the whole top control row), while `MapScreen` keeps owning the `@State` booleans and the `.sheet` presentations they drive (only *toggling* those booleans moves into `MapFilterControls`, via bindings).

- [ ] **Step 1: Rewrite `MapFilterControls.swift`**

```swift
import SwiftUI

struct MapFilterControls: View {
    @Bindable var model: MapModel
    @Binding var showPersonalPinList: Bool
    @Binding var showRoutePlanner: Bool
    @State private var showFilters = false
    @Environment(ProEntitlementModel.self) private var proEntitlementModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    favoritesButton
                    if proEntitlementModel.isProEntitled {
                        routePlannerButton
                    }
                    searchField
                    filterToggleButton
                }
            }
            GlassEffectContainer(spacing: 12) {
                VStack(alignment: .trailing, spacing: 12) {
                    if showFilters {
                        categoryChips
                    }
                    if proEntitlementModel.isProEntitled {
                        hideFoundButton
                    }
                }
            }
        }
        .padding(16)
    }

    private var favoritesButton: some View {
        Button {
            showPersonalPinList = true
        } label: {
            Image(systemName: "star.circle")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var routePlannerButton: some View {
        Button {
            showRoutePlanner = true
        } label: {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var filterToggleButton: some View {
        Button {
            withAnimation(.snappy) { showFilters.toggle() }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var hideFoundButton: some View {
        Button {
            model.hideFoundPOIs.toggle()
        } label: {
            Text("map.hideFound.toggle")
                .font(.caption)
                .foregroundStyle(model.hideFoundPOIs ? NCColor.neonCyan : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var searchField: some View {
        TextField("map.search.placeholder", text: $model.searchQuery)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)
    }

    private var categoryChips: some View {
        ForEach(POICategory.allCases, id: \.self) { category in
            let isActive = model.activeCategories.contains(category)
            Button {
                toggle(category)
            } label: {
                Text(category.localizedNameKey)
                    .font(.caption)
                    .foregroundStyle(isActive ? NCColor.neonCyan : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func toggle(_ category: POICategory) {
        if model.activeCategories.contains(category) {
            model.activeCategories.remove(category)
        } else {
            model.activeCategories.insert(category)
        }
    }
}
```

- [ ] **Step 2: Update `MapScreen.swift` — remove the favorites/route button block from `mapCanvas`, pass bindings into `MapFilterControls`, change the outer `ZStack` alignment**

In `content(model:)`, change BOTH branches' `ZStack(alignment: .topTrailing)` to `ZStack(alignment: .top)`, and pass the two new bindings to `MapFilterControls`:

```swift
    @ViewBuilder
    private func content(model: MapModel) -> some View {
        if sizeClass == .compact {
            ZStack(alignment: .top) {
                mapCanvas(model: model)
                MapFilterControls(
                    model: model,
                    showPersonalPinList: $showPersonalPinList,
                    showRoutePlanner: $showRoutePlanner
                )
            }
            .sheet(item: Binding(get: { model.selectedPOI }, set: { model.selectedPOI = $0 })) { poi in
                POIDetailView(
                    poi: poi,
                    isFound: model.isFound(poi),
                    onToggleFound: { model.toggleFound(poi) },
                    onDismiss: { model.selectedPOI = nil }
                )
                .presentationDetents([.medium])
            }
        } else {
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    mapCanvas(model: model)
                    MapFilterControls(
                        model: model,
                        showPersonalPinList: $showPersonalPinList,
                        showRoutePlanner: $showRoutePlanner
                    )
                }
                if let selected = model.selectedPOI {
                    POIDetailView(
                        poi: selected,
                        isFound: model.isFound(selected),
                        onToggleFound: { model.toggleFound(selected) },
                        onDismiss: { model.selectedPOI = nil }
                    )
                    .frame(width: 340)
                    .transition(.move(edge: .trailing))
                }
            }
        }
    }
```

Then in `mapCanvas(model:)`, remove the favorites/route-planner button `VStack` (the block starting `VStack(spacing: 12) { Button { showPersonalPinList = true } ...` through its closing `.padding(16)`) entirely — everything else in `mapCanvas` (the `TiledMapRepresentable`, `MapPinsOverlay`, `PersonalPinsOverlay`, the community-spots `ForEach`, and every `.onAppear`/`.sheet`/`.alert`/`.confirmationDialog` modifier attached to it, including the `.sheet(isPresented: $showPersonalPinList)` and `.sheet(isPresented: $showRoutePlanner)` ones) stays completely unchanged — those two `@State` booleans still live in `MapScreen` and their sheets are still presented from `mapCanvas`; only the buttons that *set* them move into `MapFilterControls`.

- [ ] **Step 3: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator, open the Map tab, and confirm: the favorites bubble, search field, and filter toggle now sit in one row spanning most of the screen width, with the search field visibly filling the space between the favorites bubble and the toggle button (not a fixed narrow box anymore). Confirm tapping the favorites button still opens the personal-pins sheet, and (as a Pro user, if reachable) tapping the route-planner button still opens the route planner sheet — both are unchanged in behavior, only relocated. Test on both compact and regular width per the iPad-first-class constraint.

- [ ] **Step 4: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass — `MapModelTests` unaffected (no model change), this is pure view restructuring.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Map/MapFilterControls.swift NeonCompass/Features/Map/MapScreen.swift
git commit -m "fix: unify the map's top controls into one row so the search field fills the space between the favorites bubble and the filter toggle"
```

## Task 4: Tab bar — "Progression" label no longer wraps to two lines

**Files:**
- Modify: `NeonCompass/App/CompactTabBar.swift`

**Interfaces:**
- Consumes: nothing from other tasks.

**Context:** French's `tab.progress` = "Progression" (11 characters) is longer than English's "Progress" and wraps to two lines under the icon at `.caption2` size in a narrow per-tab column (5 tabs sharing the screen width) — `Text(tab.titleKey)` currently has no `.lineLimit`/`.minimumScaleFactor`, so SwiftUI wraps rather than shrinking it.

- [ ] **Step 1: Constrain the tab label to one line, shrinking if needed**

In `NeonCompass/App/CompactTabBar.swift`, change `tabButton(_:)`:

```swift
    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20))
                Text(tab.titleKey)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selection == tab ? NCColor.neonCyan : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular.interactive())
    }
```
(Only the `Text(tab.titleKey)` line gains `.lineLimit(1)` and `.minimumScaleFactor(0.75)` — everything else in the file is unchanged.)

- [ ] **Step 2: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator with the device set to French (or temporarily read the French string to confirm the rendered width), and confirm "Progression" now renders on one line (shrunk slightly if needed) under the Progress tab's icon, matching the other four tabs' single-line labels.

- [ ] **Step 3: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass (pure view-styling change, `AppTabTests` unaffected).

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/App/CompactTabBar.swift
git commit -m "fix: keep the bottom tab bar's Progression label on one line instead of wrapping"
```

## Self-Review

**Spec coverage:** all four follow-up items are covered — ad banner sizing (Task 1), map full-screen cover-fit with real pan/zoom (Task 2), unified search row filling the gap between favorites and the filter toggle (Task 3), Progression tab label wrap (Task 4).

**Placeholder scan:** every task has complete, real code; the root cause for each was established by reading the actual current files (post-Round-1) before writing this plan, not guessed.

**Type consistency:** `MapGeometry.coverZoomScale`/`centeredContentOffset` are defined once in Task 2 and consumed only by `TiledMapView.swift` in the same task. `MapFilterControls`'s new `showPersonalPinList`/`showRoutePlanner` binding parameters are introduced in Task 3 and its only caller (`MapScreen.swift`) is updated in the same task — no other file constructs `MapFilterControls`.

**Known limitation, disclosed rather than engineered around:** Task 1's `bannerClearance` constant (+110) is a conservative estimate, not a measurement — the real ad height is only known once `BannerAdView` itself measures its width at runtime, and duplicating that measurement in the parent screens purely to size a scroll-content padding would add real complexity for a cosmetic safety margin. If a future ad format is taller than 110pt total, the scroll content's last row could briefly sit behind the bubble — worth revisiting if that's ever observed.

**Deliberately out of scope:** the GTA V / dual-game switch feature raised separately by the user is not folded into this plan — that needs its own dedicated scoping conversation.
