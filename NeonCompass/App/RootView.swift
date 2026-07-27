import GoogleMobileAds
import SwiftData
import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @State private var onboarding = OnboardingModel()
    @State private var authModel = AuthModel(authProvider: FirebaseAuthProvider())
    @State private var proEntitlementModel: ProEntitlementModel
    // Constructed with a reference to proEntitlementModel, so it can't be a
    // plain `@State private var x = ...` default (those can't reference
    // `self`/sibling properties) — built in `init()` instead.
    @State private var widgetSummaryCoordinator: WidgetSummaryCoordinator
    @State private var themeStore = ThemeStore()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext

    init() {
        let proEntitlementModel = ProEntitlementModel(provider: StoreKitProProvider())
        _proEntitlementModel = State(initialValue: proEntitlementModel)
        _widgetSummaryCoordinator = State(initialValue: WidgetSummaryCoordinator(
            writer: AppGroupWidgetSummaryWriter(),
            proEntitlementModel: proEntitlementModel
        ))
    }

    var body: some View {
        Group {
            if onboarding.needsDisclaimer {
                DisclaimerView { onboarding.acceptDisclaimer() }
            } else if onboarding.needsATTPrompt {
                ProgressView()
                    .task { await onboarding.requestTrackingAuthorization() }
            } else if onboarding.needsConsentPrompt {
                ProgressView()
                    .task { await onboarding.requestConsent() }
            } else if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .environment(authModel)
        .environment(proEntitlementModel)
        .environment(widgetSummaryCoordinator)
        .environment(themeStore)
        .preferredColorScheme(.dark)
        // Makes the Pro theme picker's selection a real, app-wide effect:
        // the selected accent becomes the default tint for any control that
        // doesn't already have a more specific, explicit `.tint(...)` override
        // (e.g. the deliberate sunsetMagenta/neonCyan call sites elsewhere
        // stay as-is). `ThemeStore` is `@Observable`, so this recomputes
        // whenever `selectTheme(_:)` mutates `selectedTheme`.
        .tint(themeStore.selectedTheme.accent)
        // Starts Mobile Ads only once every onboarding gate (disclaimer,
        // ATT, UMP consent) has cleared — never before consent is resolved
        // (spec §RGPD: consent gate is mandatory, not bypassable). Keyed on
        // needsConsentPrompt (the last gate to flip false) so this fires
        // exactly once, right after that transition, rather than re-running
        // on every unrelated state change.
        .task(id: onboarding.needsConsentPrompt) {
            guard !onboarding.needsDisclaimer, !onboarding.needsATTPrompt, !onboarding.needsConsentPrompt else { return }
            MobileAds.shared.start()
        }
        .task {
            // Seeds the widget with real data at launch, BEFORE the user ever
            // visits Progression/Cheats (those screens only construct their
            // models lazily on first appearance — see `WidgetSummaryCoordinator`'s
            // doc comment). Without this, a Pro user who adds the widget but
            // starts on the default Feed tab would see 0%/no-favorite-cheat
            // even if real `FoundEntry`/`FavoriteCheat` data already exists.
            hydrateWidgetSummaryFromCache()
            await proEntitlementModel.refresh()
        }
        // Nothing else subscribes to entitlement changes on their own —
        // `WidgetSummaryCoordinator` otherwise only rewrites the widget
        // summary as a side effect of unrelated Progression/Cheats updates.
        // Without this, buying Pro (or restoring a purchase) wouldn't
        // unlock the widget until one of those unrelated events happened
        // to fire.
        .onChange(of: proEntitlementModel.isProEntitled) { _, _ in
            widgetSummaryCoordinator.refresh()
        }
    }

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            screen(for: model.selectedTab)
            CompactTabBar(selection: $model.selectedTab)
        }
    }

    private var regularLayout: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    screen(for: tab)
                } label: {
                    Label(tab.titleKey, systemImage: tab.systemImage)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    /// Seeds `widgetSummaryCoordinator` from cached SwiftData/`ContentStore`
    /// state, independent of whether Progression or Cheats has ever been
    /// visited this app-lifetime. Reuses `ProgressionModel`/`CheatsModel`
    /// themselves (rather than re-deriving `overallProgress`/favorite-cheat-
    /// title logic here) so there's exactly one place that formula lives.
    /// Both instances are read-only in effect here (never awaited on
    /// `syncIfNeeded()`, never mutated) and are discarded immediately after
    /// their `init` notifies the coordinator — they don't race with the
    /// screens' own later, independent construction: whichever write lands
    /// last (this one now, or a tab visit later with freshly-synced content)
    /// simply wins, and both always write the full coherent `WidgetSummary`.
    private func hydrateWidgetSummaryFromCache() {
        let poiStore = ContentStore<POI>(
            collectionName: "poi",
            remote: FirestoreContentRepository<POI>(collectionName: "poi"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        _ = ProgressionModel(
            pois: poiStore.items + POILoader.bundled,
            trophies: [],
            modelContext: modelContext,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )

        let cheatStore = ContentStore<Cheat>(
            collectionName: "cheats",
            remote: FirestoreContentRepository<Cheat>(collectionName: "cheats"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        _ = CheatsModel(
            cheats: cheatStore.items,
            modelContext: modelContext,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedScreen()
        case .map: MapScreen()
        case .cheats: CheatsScreen()
        case .progress: ProgressionScreen()
        case .profile: ProfileScreen()
        }
    }
}
