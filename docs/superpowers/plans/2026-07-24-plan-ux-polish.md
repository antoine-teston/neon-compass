# UI/UX Polish (Feed/Cheats ads, Map bugs, Progression, Profile, Paywall) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix a concrete, user-reported list of UI/UX problems across six screens — Feed/Cheats ad banner placement, the Cheats/Guides switcher, three Map layout bugs (centering, navigation, a full-screen black box), the search/favorites bubble overlap, category-chip expand direction, a Progression screen visual cleanup, a missing Profile level/XP display, and Paywall text/icon misalignment.

**Architecture:** Each task is scoped to one screen/bug cluster and touches only the files that screen owns. The riskiest piece — the Map's centering/black-box fix — moves the fit/center math into small pure functions on `MapGeometry` (unit-testable with Swift Testing, no UIKit dependency), keeping the UIKit `TiledMapView.swift` a thin shell that just calls them, consistent with this project's existing "pure core, thin UIKit/platform shell" convention (e.g. `InterstitialCapPolicy`).

**Tech Stack:** SwiftUI, UIKit (`CATiledLayer`/`UIScrollView`, one file only per CLAUDE.md), Swift Testing.

## Global Constraints

- **Localization (CLAUDE.md):** every user-facing string goes through the String Catalog (`NeonCompass/Resources/Localizable.xcstrings`) — no hardcoded literals. Task 6 adds exactly two new keys and must populate all five locales (en/fr/es/it/de) for both, matching the file's exact existing formatting (2-space indent, `"key" : value` with a space before *and* after the colon — see the Localizable.xcstrings surgical-edit rule below).
- **Localizable.xcstrings surgical-edit rule (established in Plans 6b-2/6b-3/6c):** never reserialize the whole file via a full JSON parse-then-dump. Insert new key blocks as targeted text insertions at the exact position given in the task, preserving the file's existing formatting exactly.
- **IP constraint (CLAUDE.md, spec §1):** no Rockstar/Take-Two trademarks anywhere. This plan introduces no new game-content strings, so this is a background constraint, not an active concern — flag it if any task's execution surfaces new user-facing copy beyond what's specified here.
- **iPad-first-class (CLAUDE.md):** every fix must be checked against both size classes (`sizeClass == .compact` vs regular/`sidebarAdaptable`) where the file in question branches on `horizontalSizeClass` — don't fix the iPhone case while silently breaking or ignoring the iPad case.
- **Swift 6 strict concurrency, SwiftUI only** (CLAUDE.md) — no new UIKit beyond the single existing `TiledMapView.swift` file already permitted for `CATiledLayer`.
- **Tests: Swift Testing, not XCTest** (CLAUDE.md) for any new test code.
- **No manual UI/tap automation exists in this repo** (no UI test target — confirmed in `project.yml`, only a unit test target). Every task that changes visible layout must still (a) extract genuinely pure, unit-testable logic wherever the fix has a computable core (the Map centering fix is the clearest case), and (b) get a real Simulator visual check by the implementer using `Scripts/build.sh` + manual navigation, with results reported honestly — a task that could not be visually confirmed (e.g. because reaching a screen requires sign-in) must say so plainly rather than claim an unverified fix "looks right."

## File Structure

- Modify: `NeonCompass/Features/Feed/FeedListView.swift` — Task 1 (ad banner glass bubble).
- Modify: `NeonCompass/Features/Cheats/CheatsListView.swift` — Task 1 (ad banner glass bubble).
- Create: `NeonCompass/Core/DesignSystem/NCLayout.swift` — Task 1 (shared layout constant).
- Modify: `NeonCompass/Features/Cheats/CheatsScreen.swift` — Task 2 (remove Guides section, temporarily).
- Modify: `NeonCompass/Core/Map/MapGeometry.swift` — Task 3 (new pure fit/center functions + `ContentInsets` type).
- Modify: `NeonCompass/Core/Map/TiledMapView.swift` — Task 3 (dynamic fit-to-bounds scroll view).
- Modify: `NeonCompassTests/Map/MapGeometryTests.swift` — Task 3 (tests for the new pure functions).
- Modify: `NeonCompass/Features/Map/MapFilterControls.swift` — Task 4 (width cap + chip reordering).
- Modify: `NeonCompass/Features/Progression/ProgressionListView.swift` — Task 5 (unified card layout).
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift` — Task 6 (level/XP display).
- Modify: `NeonCompass/Resources/Localizable.xcstrings` — Task 6 (two new keys, all 5 locales).
- Modify: `NeonCompass/Features/Store/PaywallView.swift` — Task 7 (fixed-width icon `LabelStyle`).

## Task 1: Ad banner as a glass bubble above the bottom tab bar (Feed + Cheats)

**Files:**
- Create: `NeonCompass/Core/DesignSystem/NCLayout.swift`
- Modify: `NeonCompass/Features/Feed/FeedListView.swift`
- Modify: `NeonCompass/Features/Cheats/CheatsListView.swift`

**Interfaces:**
- Produces: `NCLayout.compactTabBarClearance` (`CGFloat`) — the shared constant both files use to keep their floating ad bubble clear of `CompactTabBar` on compact width.
- Consumes: nothing new from other tasks.

**Context:** Today, in both `FeedListView.swift` and `CheatsListView.swift`, `BannerAdView()` is just a plain, non-glass `.frame(height: 50)` row appended at the end of the scrolling content `VStack` — it scrolls away with the list and has no relationship to `CompactTabBar` (which floats over content via a `ZStack(alignment: .bottom)` in `RootView.compactLayout`, with no shared geometry). The fix pins the banner as a distinct glass "bubble" near the bottom of the screen, above the floating tab bar on compact width, and above the system tab/sidebar bar's own reserved safe area on regular width (regular-width `TabView(.sidebarAdaptable)` already reserves its own safe area for Tab content, so no extra padding is needed there — the constant is deliberately only applied when `sizeClass == .compact`).

- [ ] **Step 1: Create the shared layout constant**

```swift
import CoreGraphics

/// Layout constants that don't belong in the color/typography design-system
/// files. `CompactTabBar` has no fixed height of its own (Liquid Glass
/// containers size to content — its tallest element is the 60pt map button,
/// floated -12pt above the row), so this is a deliberately approximate,
/// hand-tuned clearance value rather than a measured one. Re-tune if
/// `CompactTabBar`'s content changes.
enum NCLayout {
    static let compactTabBarClearance: CGFloat = 78
}
```
Save as `NeonCompass/Core/DesignSystem/NCLayout.swift`.

- [ ] **Step 2: Rewrite `FeedListView.swift` to pin the ad banner as a glass bubble**

```swift
import SwiftUI

struct FeedListView: View {
    @Bindable var model: FeedModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.newsItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.newsItems) { item in
                            card(for: item)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, proEntitlementModel.isProEntitled ? 0 : bannerClearance)
            }
            if !proEntitlementModel.isProEntitled {
                adBanner
            }
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    /// Room reserved at the bottom of the scrolling content so the last card
    /// never sits behind the floating ad bubble (≈50pt banner + its own
    /// padding) stacked above the compact tab bar.
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

    private func card(for item: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(categoryTitleKey(item.category), systemImage: categorySymbol(item.category))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            Text(item.title.resolved(for: currentLanguageCode))
                .font(NCTypography.displayTitle)
                .foregroundStyle(.white)

            Text(item.body.resolved(for: currentLanguageCode))
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.system(size: 32))
                .foregroundStyle(NCColor.neonCyan)
            Text("feed.empty")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private func categoryTitleKey(_ category: NewsCategory) -> LocalizedStringKey {
        switch category {
        case .announcement: "feed.category.announcement"
        case .patch: "feed.category.patch"
        case .event: "feed.category.event"
        }
    }

    private func categorySymbol(_ category: NewsCategory) -> String {
        switch category {
        case .announcement: "megaphone"
        case .patch: "wrench.and.screwdriver"
        case .event: "calendar"
        }
    }
}
```

- [ ] **Step 3: Rewrite `CheatsListView.swift` the same way**

```swift
import SwiftUI

struct CheatsListView: View {
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 12) {
                    platformToggle
                    TextField("cheats.search.placeholder", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: .capsule)

                    ForEach(model.filteredCheats) { cheat in
                        CheatCard(
                            cheat: cheat,
                            platform: model.activePlatform,
                            isFavorite: model.isFavorite(cheat),
                            onTap: { onSelect(cheat) },
                            onToggleFavorite: { model.toggleFavorite(cheat) }
                        )
                    }
                }
                .padding(16)
                .padding(.bottom, proEntitlementModel.isProEntitled ? 0 : bannerClearance)
            }
            if !proEntitlementModel.isProEntitled {
                adBanner
            }
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

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

    private var platformToggle: some View {
        Picker("cheats.platform.picker", selection: $model.activePlatform) {
            Text("cheats.platform.ps5").tag(Platform.ps5)
            Text("cheats.platform.xbox").tag(Platform.xbox)
        }
        .pickerStyle(.segmented)
    }
}
```

- [ ] **Step 4: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Then launch the app in Simulator (iPhone destination — `Scripts/simulator-destination.sh` prints the configured one), navigate to the Feed tab and the Cheats tab as a non-Pro (free) user, and confirm: the ad banner renders as a distinct rounded glass bubble sitting just above the floating bottom tab bar, not overlapping it, and scrolling the list never reveals content clipped behind the bubble. Report the observation plainly in the task report — if sign-in/Pro-state makes verifying the free-user banner state impractical in this pass, say so explicitly rather than claim it visually confirmed.

- [ ] **Step 5: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all existing tests still pass (no logic changed, layout only).

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Core/DesignSystem/NCLayout.swift NeonCompass/Features/Feed/FeedListView.swift NeonCompass/Features/Cheats/CheatsListView.swift
git commit -m "fix: pin the ad banner as a glass bubble above the bottom tab bar on Feed and Cheats"
```

## Task 2: Remove the Guides section from Cheats (temporary, pending redesign)

**Files:**
- Modify: `NeonCompass/Features/Cheats/CheatsScreen.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing new — `GuidesModel`, `GuidesListView`, `GuideDetailView`, `Guide.swift`, and the `ContentStore<Guide>`/Firestore `guides` collection pipeline are all left completely intact and untouched. Confirmed (via research before writing this plan) that nothing outside `CheatsScreen.swift` references any of those types — hiding Guides here has zero side effects elsewhere.

**Context:** The user wants a different design for switching between Cheats and Guides, but doesn't have one yet — the instruction is to remove Guides from the UI for now rather than ship a half-considered switcher. This is a pure UI change: delete the segmented picker and the `.guides` branch, and always show Cheats content directly. `GuidesModel`/`GuidesListView`/`GuideDetailView`/`Guide.swift` stay in the repo unmodified so the eventual redesign has all its groundwork intact.

- [ ] **Step 1: Simplify `CheatsScreen.swift` to show only Cheats**

```swift
import SwiftUI
import SwiftData

struct CheatsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSummaryCoordinator.self) private var widgetSummaryCoordinator
    @State private var model: CheatsModel?
    @State private var readerCheat: Cheat?

    // Guides is temporarily removed from this screen pending a redesign of
    // how users switch between Cheats and Guides (the previous segmented
    // Picker wasn't the right UX) — GuidesModel/GuidesListView/
    // GuideDetailView/Guide.swift are untouched and ready to be reattached
    // once that design exists.

    var body: some View {
        Group {
            if let model {
                cheatsContent(model: model)
            } else {
                ProgressView().task { await loadCheatsModel() }
            }
        }
    }

    private func cheatsContent(model: CheatsModel) -> some View {
        CheatsListView(model: model) { cheat in
            readerCheat = cheat
        }
        .fullScreenCover(item: $readerCheat) { cheat in
            if let index = model.filteredCheats.firstIndex(where: { $0.id == cheat.id }) {
                CheatReaderView(
                    cheats: model.filteredCheats,
                    startIndex: index,
                    platform: model.activePlatform,
                    onDismiss: { readerCheat = nil }
                )
            }
        }
    }

    private func loadCheatsModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<Cheat>(
            collectionName: "cheats",
            remote: FirestoreContentRepository<Cheat>(collectionName: "cheats"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = CheatsModel(
            cheats: contentStore.items,
            modelContext: modelContext,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )
        try? await contentStore.syncIfNeeded()
        model?.updateCheats(contentStore.items)
    }
}
```

- [ ] **Step 2: Build and run the full test suite**

Run: `Scripts/build.sh` then `Scripts/test.sh`
Expected: `** BUILD SUCCEEDED **`, all tests pass. `GuidesModelTests` (existing, in `NeonCompassTests/Guides/`) must still pass unchanged — they test `GuidesModel` directly, not through `CheatsScreen`, so removing the screen's picker must not affect them.

- [ ] **Step 3: Commit**

```bash
git add NeonCompass/Features/Cheats/CheatsScreen.swift
git commit -m "fix: temporarily remove the Cheats/Guides switcher pending a better design (GuidesModel/GuidesListView untouched)"
```

## Task 3: Map — fit-to-bounds centering (fixes "not centered", "can't navigate fully", and the full-screen black box)

**Files:**
- Modify: `NeonCompass/Core/Map/MapGeometry.swift`
- Modify: `NeonCompass/Core/Map/TiledMapView.swift`
- Modify: `NeonCompassTests/Map/MapGeometryTests.swift`

**Interfaces:**
- Produces: `MapGeometry.fitZoomScale(contentSize:in:) -> CGFloat` and `MapGeometry.centeringInsets(contentSize:zoomScale:in:) -> ContentInsets`, plus a new `ContentInsets` struct (`top`/`left`/`bottom`/`right` `CGFloat`, `CoreGraphics`-only, no UIKit dependency so it stays testable without a simulator).
- Consumes: nothing from other tasks.

**Context — root cause, established by reading the actual files (not guessed):** `TiledMapView.swift`'s `makeUIView` sets `scrollView.minimumZoomScale = 1 / CGFloat(1 << manifest.maxZoom)` — a fixed formula based purely on tile-pyramid depth (currently `1/8` for `maxZoom = 3`), completely independent of the device's actual screen size. With `fullSize = 256 * 8 = 2048` and `zoomScale` set to that fixed `1/8`, the displayed map is always exactly `256×256` points on screen, regardless of whether the device is an iPhone SE or an iPad Pro. Since `contentOffset` is never set (stays UIKit's default `.zero`, i.e. top-left) and both the canvas and scroll view have `backgroundColor = .black`, the result is: a tiny `256×256`-point map pinned in the top-left corner, with the remaining ~80%+ of the screen showing plain black scroll-view background. This single root cause explains all three reported symptoms at once — "not centered" (content sits top-left), "big black box" (the uncovered remainder of the screen is the scrollView's own black background, not a tile-rendering failure — the 85 bundled tile PNGs are real, valid images, confirmed on disk), and "can't navigate fully" (panning around a mostly-empty, wrongly-scaled canvas feels broken even though `UIScrollView` itself has no artificial pan/zoom restriction).

The fix: compute `minimumZoomScale` from the scroll view's *actual* bounds once real layout has happened (not a fixed formula), and center the resulting (likely smaller-than-viewport) content via `contentInset`/`contentOffset`. `bounds` isn't reliably known yet inside `makeUIView` (SwiftUI hasn't laid the view out at that point), so this must happen in a scroll view subclass's `layoutSubviews()`, guarded to run only when `bounds.size` actually changes (first layout, or a rotation) — never on every layout pass, so it never fights a live pinch-zoom/pan gesture (those don't change `bounds.size`, only `zoomScale`/`contentOffset`, which this guard doesn't touch).

- [ ] **Step 1: Write the failing tests for the new pure functions**

Add to `NeonCompassTests/Map/MapGeometryTests.swift` (append inside the existing `struct MapGeometryTests`, after `normalizedPointFromCanvasPointIsZoomIndependent`):

```swift
    @Test func fitZoomScaleShrinksToFitTheSmallerDimension() {
        // contentSize 2048x2048, bounds 390x844 (iPhone-shaped) — width is
        // the binding constraint: 390/2048 < 844/2048.
        let scale = MapGeometry.fitZoomScale(contentSize: CGSize(width: 2048, height: 2048), in: CGSize(width: 390, height: 844))
        #expect(abs(scale - 390.0 / 2048.0) < 0.0001)
    }

    @Test func fitZoomScaleNeverUpscalesPastOne() {
        // Content smaller than the viewport must never be blown up past its
        // native resolution — this is a fully-zoomed-out map, not a photo.
        let scale = MapGeometry.fitZoomScale(contentSize: CGSize(width: 100, height: 100), in: CGSize(width: 390, height: 844))
        #expect(scale == 1)
    }

    @Test func fitZoomScaleIsOneForDegenerateInput() {
        #expect(MapGeometry.fitZoomScale(contentSize: .zero, in: CGSize(width: 390, height: 844)) == 1)
        #expect(MapGeometry.fitZoomScale(contentSize: CGSize(width: 2048, height: 2048), in: .zero) == 1)
    }

    @Test func centeringInsetsCentersSmallerContentOnBothAxes() {
        // Scaled content 200x200 inside a 300x400 viewport: 50pt horizontal
        // margin each side, 100pt vertical margin each side.
        let insets = MapGeometry.centeringInsets(
            contentSize: CGSize(width: 200, height: 200),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(insets == ContentInsets(top: 100, left: 50, bottom: 100, right: 50))
    }

    @Test func centeringInsetsClampToZeroWhenContentFillsOrExceedsAnAxis() {
        // Scaled content 500x500 exceeds both axes of a 300x400 viewport —
        // insets must clamp to 0, never go negative.
        let insets = MapGeometry.centeringInsets(
            contentSize: CGSize(width: 500, height: 500),
            zoomScale: 1,
            in: CGSize(width: 300, height: 400)
        )
        #expect(insets == ContentInsets(top: 0, left: 0, bottom: 0, right: 0))
    }
```

- [ ] **Step 2: Run the tests to confirm they fail to compile (the functions don't exist yet)**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/MapGeometryTests`
Expected: build failure — `MapGeometry.fitZoomScale`/`centeringInsets`/`ContentInsets` not found.

- [ ] **Step 3: Add the pure functions to `MapGeometry.swift`**

```swift
import CoreGraphics

/// État de zoom/pan de l'UIScrollView, poussé par TiledMapRepresentable
/// (Task 5) vers la couche SwiftUI pour positionner pins et overlays.
struct MapViewport: Equatable, Sendable {
    var zoomScale: CGFloat = 1
    var contentOffset: CGPoint = .zero
}

/// Symmetric margin needed to center scaled map content within a viewport —
/// `CoreGraphics`-only (no UIKit), so it stays unit-testable without a
/// simulator; `TiledMapView.swift` converts this to `UIEdgeInsets`.
struct ContentInsets: Equatable, Sendable {
    var top: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var right: CGFloat = 0
}

enum MapGeometry {
    static func fullSize(for manifest: TileManifest) -> CGFloat {
        CGFloat(manifest.tileSize * (1 << manifest.maxZoom))
    }

    static func screenPosition(for point: NormalizedPoint, manifest: TileManifest, viewport: MapViewport) -> CGPoint {
        let full = fullSize(for: manifest)
        return CGPoint(
            x: CGFloat(point.x) * full * viewport.zoomScale - viewport.contentOffset.x,
            y: CGFloat(point.y) * full * viewport.zoomScale - viewport.contentOffset.y
        )
    }

    /// `point` est en coordonnées du canvas UIKit plein-résolution (Task 5),
    /// pas du viewport visible — indépendant du zoom/pan courant.
    static func normalizedPoint(fromCanvasPoint point: CGPoint, manifest: TileManifest) -> NormalizedPoint {
        let full = fullSize(for: manifest)
        return NormalizedPoint(x: Double(point.x / full), y: Double(point.y / full))
    }

    /// The zoom scale at which `contentSize` fits entirely within `bounds`
    /// (aspect-fit on the more constraining axis), never upscaled past 1 —
    /// this is a fully-zoomed-out map, not a photo that should ever render
    /// larger than its native pixel resolution. Returns 1 for degenerate
    /// (zero-sized) input rather than dividing by zero.
    static func fitZoomScale(contentSize: CGSize, in bounds: CGSize) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        return min(scale, 1)
    }

    /// The symmetric inset needed to center content of `contentSize` scaled
    /// by `zoomScale` within `bounds` — clamped to zero on any axis where the
    /// scaled content already fills or exceeds that axis of `bounds` (never
    /// negative).
    static func centeringInsets(contentSize: CGSize, zoomScale: CGFloat, in bounds: CGSize) -> ContentInsets {
        let scaledWidth = contentSize.width * zoomScale
        let scaledHeight = contentSize.height * zoomScale
        let horizontal = max((bounds.width - scaledWidth) / 2, 0)
        let vertical = max((bounds.height - scaledHeight) / 2, 0)
        return ContentInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}
```

- [ ] **Step 4: Run the tests again — should pass now**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/MapGeometryTests`
Expected: all pass, including the 5 new tests.

- [ ] **Step 5: Wire the fit/center logic into `TiledMapView.swift`**

Replace the fixed-formula zoom setup in `makeUIView` with a dynamic, bounds-aware scroll view subclass:

```swift
import SwiftUI
import UIKit

/// Seule pièce UIKit du moteur de carte — CATiledLayer n'a pas d'équivalent
/// SwiftUI. Toute la logique zoom/pan/tuiles est isolée ici (CLAUDE.md :
/// "UIKit seulement si une API l'impose, wrapped in one file").

/// Charge une tuile PNG pré-rendue depuis le folder reference bundlé (Task 1).
private enum TilePyramid {
    static func image(z: Int, x: Int, y: Int, bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: "\(y)", withExtension: "png", subdirectory: "MapTiles/\(z)/\(x)") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

/// Vue support de CATiledLayer. Le niveau de zoom courant se lit dans la CTM
/// du contexte au moment de draw(_:) — technique standard pour afficher une
/// pyramide de tuiles pré-rendues (cf. l'échantillon Apple "PhotoScroller").
private final class TiledCanvasView: UIView {
    override class var layerClass: AnyClass { CATiledLayer.self }

    private let manifest: TileManifest

    init(manifest: TileManifest) {
        self.manifest = manifest
        super.init(frame: .zero)
        let tiled = layer as! CATiledLayer
        tiled.tileSize = CGSize(width: manifest.tileSize, height: manifest.tileSize)
        // levelsOfDetail = total pyramid levels (magnified + normal + reduced);
        // levelsOfDetailBias = how many of those are magnified (scale > 1).
        // maximumZoomScale is 1 here (no magnification), so bias stays 0;
        // minimumZoomScale is computed dynamically to fit the real viewport,
        // so we still need maxZoom reduced levels below normal resolution,
        // i.e. levelsOfDetail = maxZoom + 1.
        tiled.levelsOfDetail = manifest.maxZoom + 1
        tiled.levelsOfDetailBias = 0
        contentScaleFactor = 1
        isOpaque = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    nonisolated override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let scale = ctx.ctm.a
        guard scale > 0 else { return }
        let z = max(0, min(manifest.maxZoom, Int(round(log2(scale))) + manifest.maxZoom))
        let tileSizeInPoints = CGFloat(manifest.tileSize) / scale
        let x = Int(rect.origin.x / tileSizeInPoints)
        let y = Int(rect.origin.y / tileSizeInPoints)
        guard let image = TilePyramid.image(z: z, x: x, y: y) else { return }
        image.draw(in: rect)
    }
}

/// Computes and applies a fit-to-bounds zoom scale + centering inset once the
/// scroll view's real bounds are known — `minimumZoomScale`/`zoomScale` can't
/// be set correctly in `makeUIView` because SwiftUI hasn't laid the view out
/// yet at that point (bounds is still `.zero`). Only recomputes when
/// `bounds.size` genuinely changes (first layout, or a rotation) — never on
/// every layout pass, so it never fights a live pinch-zoom/pan gesture (those
/// change `zoomScale`/`contentOffset` directly without changing `bounds.size`,
/// so the guard below simply skips them).
private final class FitToBoundsScrollView: UIScrollView {
    var contentNativeSize: CGSize = .zero
    private var lastFittedBoundsSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastFittedBoundsSize,
              bounds.width > 0, bounds.height > 0,
              contentNativeSize != .zero else { return }
        lastFittedBoundsSize = bounds.size

        let fitScale = MapGeometry.fitZoomScale(contentSize: contentNativeSize, in: bounds.size)
        minimumZoomScale = fitScale
        zoomScale = fitScale

        let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: fitScale, in: bounds.size)
        contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        contentOffset = CGPoint(x: -insets.left, y: -insets.top)
    }
}

struct TiledMapRepresentable: UIViewRepresentable {
    let manifest: TileManifest
    @Binding var viewport: MapViewport
    let onLongPress: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: $viewport, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = FitToBoundsScrollView()
        let fullSize = MapGeometry.fullSize(for: manifest)
        let canvas = TiledCanvasView(manifest: manifest)
        canvas.frame = CGRect(x: 0, y: 0, width: fullSize, height: fullSize)
        scrollView.contentSize = canvas.frame.size
        scrollView.contentNativeSize = canvas.frame.size
        scrollView.addSubview(canvas)
        scrollView.maximumZoomScale = 1
        scrollView.delegate = context.coordinator
        context.coordinator.canvas = canvas
        scrollView.backgroundColor = .black
        // Deferred to the next run-loop turn: mutating the `@Binding var viewport`
        // synchronously here (still inside SwiftUI's makeUIView/update pass) is the
        // classic "modifying state during view update" hazard — sibling views in the
        // same ZStack (e.g. PersonalPinsOverlay/MapPinsOverlay) have already captured
        // the stale viewport for this render pass, and no further pass reliably picks
        // up the new value. Dispatching async lets this pass finish first, so the
        // resulting state change triggers a proper, fresh SwiftUI re-render.
        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.sync(scrollView)
        }

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        scrollView.addGestureRecognizer(longPress)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var canvas: UIView?
        @Binding private var viewport: MapViewport
        private let onLongPress: (CGPoint) -> Void

        init(viewport: Binding<MapViewport>, onLongPress: @escaping (CGPoint) -> Void) {
            _viewport = viewport
            self.onLongPress = onLongPress
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { sync(scrollView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { sync(scrollView) }

        fileprivate func sync(_ scrollView: UIScrollView) {
            viewport = MapViewport(zoomScale: scrollView.zoomScale, contentOffset: scrollView.contentOffset)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let canvas else { return }
            onLongPress(gesture.location(in: canvas))
        }
    }
}
```

Note: `MapGeometry.screenPosition(for:manifest:viewport:)` needs no change — it already subtracts `viewport.contentOffset`, and `contentOffset` naturally comes back negative when content is centered via `contentInset` (standard `UIScrollView` behavior), so pins/overlays continue to position correctly with zero changes to that function.

- [ ] **Step 6: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator, open the Map tab, and confirm: the map appears centered (not pinned top-left), fills a sensible portion of the screen at the initial fully-zoomed-out level (not a tiny 256×256pt square), there is no large solid-black area covering most of the screen, and pinch-zoom/pan work smoothly across the whole visible map without any artificial restriction. Also rotate the Simulator (if on an iPad destination) and confirm the map re-centers rather than becoming misaligned. Report exactly what was observed — this is the highest-risk fix in the plan.

- [ ] **Step 7: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all tests pass, including the new `MapGeometryTests` additions.

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Core/Map/MapGeometry.swift NeonCompass/Core/Map/TiledMapView.swift NeonCompassTests/Map/MapGeometryTests.swift
git commit -m "fix: compute the map's initial zoom/centering from the real viewport bounds instead of a fixed formula (fixes off-center map, restricted navigation, and the full-screen black box)"
```

## Task 4: Map — fix the search/favorites bubble overlap and category-chip expand direction

**Files:**
- Modify: `NeonCompass/Features/Map/MapFilterControls.swift`

**Interfaces:**
- Consumes: nothing from other tasks (independent of Task 3's scroll-view fix).

**Context:** `MapFilterControls` is anchored `.topTrailing` in `MapScreen.swift`'s outer `ZStack`, while the separate personal-pins/route-planner button stack (the "favorites bubble") is anchored `.topLeading` in `mapCanvas`'s inner `ZStack`. `MapFilterControls`'s `searchField` (a `TextField` with no width cap) is proposed the *full* available width by the outer `ZStack` (which proposes full container size to unconstrained children), so on narrower devices the whole trailing control cluster can stretch wide enough to visually collide with the top-leading bubble. Separately, `categoryChips` is currently the *first* child of the `VStack`, appearing *above* the search/toggle row — since the whole cluster is top-anchored, revealing chips pushes the toggle button down and reads as "expanding upward toward the top" rather than "dropping down below the toggle button." Both fixes are contained to this one file.

- [ ] **Step 1: Cap the search field's width and reorder the chips**

```swift
import SwiftUI

struct MapFilterControls: View {
    @Bindable var model: MapModel
    @State private var showFilters = false
    @Environment(ProEntitlementModel.self) private var proEntitlementModel

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 12) {
                    searchField
                    filterToggleButton
                }
                if showFilters {
                    categoryChips
                }
                if proEntitlementModel.isProEntitled {
                    hideFoundButton
                }
            }
        }
        .padding(16)
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
            .frame(width: 200, height: 44)
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

- [ ] **Step 2: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator, open the Map tab, and confirm: the search bubble no longer overlaps the star/route bubble in the opposite corner, and tapping the filter toggle reveals category chips growing *downward* from the toggle button rather than upward. Test on both a compact-width (iPhone) and regular-width (iPad) destination per the iPad-first-class constraint.

- [ ] **Step 3: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass (no logic changed, layout only — `MapModelTests` unaffected).

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Map/MapFilterControls.swift
git commit -m "fix: cap the map search field's width (was overlapping the favorites bubble) and expand category chips downward instead of upward"
```

## Task 5: Progression — unify the progress display into one cleaner card layout

**Files:**
- Modify: `NeonCompass/Features/Progression/ProgressionListView.swift`

**Interfaces:**
- Consumes: nothing from other tasks. `ProgressRing` (unchanged, already draws its own centered percentage label), `POICategory`, `Trophy`, `ProgressionModel`'s existing public interface (`overallProgress`, `progress(in:)`, `trophies`, `isTrophyChecked(_:)`, `toggleTrophy(_:)`) are all reused as-is — this task is layout-only.

**Context:** Today the ring has no card/background at all, the category breakdown is one shared `.glassEffect` card, and each trophy renders as its *own separate* `.glassEffect` card — three visually disconnected treatments on one screen. This unifies the ring + category breakdown into a single "overview" card (adding a per-category `ProgressView` bar alongside the existing percentage text, for a clearer at-a-glance read), and turns the trophy list into one shared card with dividers between rows instead of N separate floating cards.

- [ ] **Step 1: Rewrite `ProgressionListView.swift`**

```swift
import SwiftUI

struct ProgressionListView: View {
    @Bindable var model: ProgressionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                overviewCard
                trophyCard
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private var overviewCard: some View {
        VStack(spacing: 20) {
            ProgressRing(progress: model.overallProgress)
                .frame(width: 140, height: 140)

            VStack(spacing: 14) {
                ForEach(POICategory.allCases, id: \.self) { category in
                    categoryRow(category)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func categoryRow(_ category: POICategory) -> some View {
        let percent = model.progress(in: category)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.localizedNameKey)
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int((percent * 100).rounded()))%")
                    .font(NCTypography.body.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
            ProgressView(value: percent)
                .tint(NCColor.neonCyan)
        }
    }

    private var trophyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("progress.trophies.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            if model.trophies.isEmpty {
                Text("progress.trophies.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.trophies.enumerated()), id: \.element.id) { index, trophy in
                        trophyRow(trophy)
                        if index < model.trophies.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func trophyRow(_ trophy: Trophy) -> some View {
        Button {
            model.toggleTrophy(trophy)
        } label: {
            HStack {
                Image(systemName: model.isTrophyChecked(trophy) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.isTrophyChecked(trophy) ? NCColor.neonCyan : .white.opacity(0.4))
                Text(trophy.title.resolved(for: currentLanguageCode))
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
```

- [ ] **Step 2: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator, open the Progress tab, and confirm: the ring and category breakdown now sit inside one visually cohesive card with per-category progress bars, and the trophy list reads as a single card with divider lines between rows rather than a stack of separate floating cards.

- [ ] **Step 3: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass — `ProgressionModelTests` (existing, unchanged model) must still pass since no model logic changed, only the view.

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Progression/ProgressionListView.swift
git commit -m "polish: unify the progress ring/category breakdown and trophy list into cleaner shared cards"
```

## Task 6: Profile — surface the existing level/XP data

**Files:**
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `Profile.level: Int` and `Profile.xp: Int` (`NeonCompass/Core/Auth/Profile.swift`) — both already fetched into `ProfileModel.profile` by the existing `loadProfile(uid:)` call in `ProfileScreen`'s `.task(id: authModel.userID)`. No model/network changes needed — this is purely a missing UI surface for data that's already there.

**Context (established by reading the actual file, not guessed):** `Profile.swift` already has `let xp: Int` and `let level: Int`, computed server-side by the `createUserProfile` Cloud Function exactly per spec ("Le niveau est calculé côté serveur... jamais par le client"). `ProfileModel.profile` already carries this data once `loadProfile(uid:)` runs. But `ProfileScreen.swift`'s body never renders `.xp` or `.level` anywhere — only `.handle` (line 99) is shown. This adds a small glass badge showing both, placed right below the handle in `signedInContent`, using two new String Catalog keys (`profile.level.format`, `profile.xp.format`) localized in all 5 languages, following this project's established `Text(String(format: String(localized: "key"), value))` pattern (already used identically in `RoutePlannerSheet.swift:22` and `ContributionAnnotationView.swift:59`).

- [ ] **Step 1: Add `levelBadge` and wire it into `signedInContent`**

In `NeonCompass/Features/Profile/ProfileScreen.swift`, change `signedInContent`:

```swift
    private func signedInContent(userID: String) -> some View {
        VStack(spacing: 16) {
            Text(profileModel.profile?.handle ?? "…")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)

            if let profile = profileModel.profile {
                levelBadge(profile)
            }

            Button("profile.handle.regenerate") {
                Task { try? await profileModel.regenerateHandle() }
            }

            if let communityModel {
                myContributionsSection(communityModel)
                blockedContributorsSection(communityModel)
            }

            Button("profile.signOut") {
                try? authModel.signOut()
            }

            Button("profile.deleteAccount", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    private func levelBadge(_ profile: Profile) -> some View {
        HStack {
            Text(String(format: String(localized: "profile.level.format"), profile.level))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)
            Spacer()
            Text(String(format: String(localized: "profile.xp.format"), profile.xp))
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
```
(This only replaces the `signedInContent` function and adds the new `levelBadge` function right after it — every other function in the file is unchanged.)

- [ ] **Step 2: Add the two new String Catalog keys**

Locate the exact text `"profile.icon.title" : {` in `NeonCompass/Resources/Localizable.xcstrings` (its full existing block ends 7 lines later at a line containing just `    },`). Insert this new key block immediately after that closing `},` line (i.e. between `profile.icon.title` and `profile.myContributions.empty`, preserving alphabetical order):

```json
    "profile.level.format" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Level %d"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Level %d"
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nivel %d"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Niveau %d"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Livello %d"
          }
        }
      }
    },
```

Then locate the exact text `"profile.theme.title" : {` (its block also ends 7 lines later at a `    },` line). Insert this second new key block immediately after that closing line (i.e. between `profile.theme.title` and `progress.trophies.empty` — `"profile.xp"` sorts after every other `profile.*` key and before `progress.*`):

```json
    "profile.xp.format" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%d XP"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%d XP"
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%d XP"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%d XP"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%d XP"
          }
        }
      }
    },
```
("XP" is kept as-is across all five languages — an internationally recognized gaming abbreviation, consistent with keeping "PRO" untranslated for the Pro badge elsewhere in this same file.)

This is a targeted text insertion of two whole new key blocks — do not reserialize or reformat any other part of the file (same rule as every other `Localizable.xcstrings` edit this project has made). After inserting, confirm the file is still valid JSON: `python3 -c "import json; json.load(open('NeonCompass/Resources/Localizable.xcstrings'))"`.

- [ ] **Step 3: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator, sign in on the Profile tab (Sign in with Apple works in Simulator with a test Apple ID), and confirm a glass badge appears below the handle showing "Level N" and "N XP" with real values. If signing in isn't practical in this pass, say so plainly and instead confirm via a targeted `Scripts/test.sh` run that nothing else regressed, plus a careful manual code read confirming `profileModel.profile` is non-nil exactly when this badge would render (mirroring the existing `Text(profileModel.profile?.handle ?? "…")` guard pattern one line above).

- [ ] **Step 4: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass, including the existing `LocalizationCoverageTests` (both new keys must have all 5 locales populated, matching format specifiers across all of them — `%d` appears exactly once in every locale's value for both keys).

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Profile/ProfileScreen.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: surface the existing server-computed level/XP on the Profile screen"
```

## Task 7: Paywall — fix icon/text alignment in the feature list

**Files:**
- Modify: `NeonCompass/Features/Store/PaywallView.swift`

**Interfaces:**
- Consumes: nothing from other tasks.

**Context (established by reading the actual file):** the 7-feature list uses plain `Label(text, systemImage:)` rows with no shared icon width — SF Symbols like `"square.grid.2x2"` (wide) and `"bell"` (narrow) have different intrinsic glyph widths, so the text portion of each row starts at a different x-offset, which is the "texts aren't aligned" symptom. The fix is a custom `LabelStyle` that gives every icon a fixed-width frame, applied once to the whole feature list (a `LabelStyle` set on a container applies to every `Label` inside it via the environment, so this doesn't need to touch the `ForEach` itself).

- [ ] **Step 1: Add a fixed-icon-width `LabelStyle` and apply it to the feature list**

```swift
import SwiftUI

private struct FixedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .font(.system(size: 18))
                .frame(width: 24, alignment: .center)
            configuration.title
        }
    }
}

struct PaywallView: View {
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.dismiss) private var dismiss

    private let features: [(LocalizedStringKey, String)] = [
        ("paywall.feature.ads", "nosign"),
        ("paywall.feature.sync", "icloud"),
        ("paywall.feature.route", "map"),
        ("paywall.feature.remaining", "checklist"),
        ("paywall.feature.widgets", "square.grid.2x2"),
        ("paywall.feature.notifications", "bell"),
        ("paywall.feature.themes", "paintpalette"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("paywall.title")
                        .font(NCTypography.displayTitle)
                        .foregroundStyle(NCColor.neonCyan)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("paywall.subtitle")
                        .font(NCTypography.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(features, id: \.1) { feature in
                            Label(feature.0, systemImage: feature.1)
                                .foregroundStyle(.white)
                        }
                    }
                    .labelStyle(FixedIconLabelStyle())
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))

                    if proEntitlementModel.isProEntitled {
                        Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                            .labelStyle(FixedIconLabelStyle())
                            .foregroundStyle(NCColor.neonCyan)
                    } else {
                        Button("paywall.buy") {
                            Task { await proEntitlementModel.purchase() }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(NCColor.sunsetMagenta)

                        Button("paywall.restore") {
                            Task { await proEntitlementModel.restorePurchases() }
                        }
                    }
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("paywall.close") { dismiss() }
                }
            }
        }
    }
}
```
(Title/subtitle keep their natural center alignment — now made explicit via `.frame(maxWidth: .infinity, alignment: .center)` rather than relying on the implicit `VStack` default — while the feature list stays intentionally `.leading` for readability as a checklist; the fix that actually addresses "texts not aligned" is the icon-column alignment inside the list via `FixedIconLabelStyle`, applied to both the 7-feature list and the already-entitled Pro badge for consistency.)

- [ ] **Step 2: Build and visually verify on Simulator**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

Launch in Simulator, open the paywall (Profile → Upgrade to Pro), and confirm all 7 feature rows now have their text starting at the same horizontal position regardless of icon glyph width.

- [ ] **Step 3: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass (view-only change, no model/logic touched).

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Store/PaywallView.swift
git commit -m "fix: align paywall feature-list text via a fixed-width icon LabelStyle"
```

## Self-Review

**Spec coverage:** every item from the user's list is covered — Feed/Cheats ad banner bubble (Task 1), Cheats/Guides switcher rethink + temporary Guides removal (Task 2), map not centered / can't navigate fully / black box (Task 3), search bubble overlapping favorites bubble + category chips expanding the wrong direction (Task 4), Progression display cleanup (Task 5), Profile level/XP encart (Task 6), Paywall text alignment (Task 7).

**Placeholder scan:** every task has complete, real code (no TBD/sketches) — precise root causes were established by reading the actual current files before writing any fix, not guessed from memory.

**Type consistency:** `MapGeometry.ContentInsets`, `fitZoomScale`, `centeringInsets` are defined once in Task 3 and consumed as-is by `TiledMapView.swift` in the same task — no other task touches `MapGeometry.swift`. `NCLayout.compactTabBarClearance` is defined once in Task 1 and used identically in both `FeedListView.swift` and `CheatsListView.swift`.

**Known limitation, disclosed rather than engineered around:** this repo has no UI test target, so every visual fix in this plan relies on the implementer's own Simulator observation (build + manual navigation) rather than an automated screenshot/tap harness — each task's verification step says so explicitly and asks for an honest report rather than an unverified claim. The Map centering fix (Task 3) is the one exception with real automated coverage, since its core logic was extracted into pure, unit-tested functions.

**Deliberately out of scope:** designing the *eventual* Cheats/Guides switcher replacement (Task 2 only removes the current one), and the GTA V / dual-game switch feature mentioned separately by the user — that is large enough to need its own dedicated plan and is not folded in here.
