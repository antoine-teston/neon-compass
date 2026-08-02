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
    /// Faux par défaut : sans Cloud Functions déployées, les écrans de compte et
    /// de communauté ne mènent nulle part. Un paramètre Remote Config les
    /// rallume tous d'un coup, sans mise à jour de l'app.
    @State private var serverFeatures = ServerFeaturesModel(gate: RemoteConfigServerFeatureGate())
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
        .environment(serverFeatures)
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
            await MobileAds.shared.start()
        }
        .task {
            // Seeds the widget with real data at launch, BEFORE the user ever
            // visits Progression/Cheats (those screens only construct their
            // models lazily on first appearance — see `WidgetSummaryCoordinator`'s
            // doc comment). Without this, a Pro user who adds the widget but
            // starts on the default Feed tab would see 0%/no-favorite-cheat
            // even if real `FoundEntry`/`FavoriteCheat` data already exists.
            // AVANT toute lecture : configure la source de contenu (CDN ou
            // Firestore) pour que la première synchronisation parte déjà du bon
            // côté. Sans réseau, la valeur reste nil et tout retombe sur
            // Firestore — le comportement d'avant.
            await ContentSourceConfigurator.configureFromRemoteConfig()
            hydrateWidgetSummaryFromCache()
            await proEntitlementModel.refresh()
            await serverFeatures.refresh()
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

    /// Onglets déjà visités, donc construits. Sert à reproduire en compact la
    /// sémantique que `TabView` offre gratuitement en régulier : un onglet est
    /// bâti à sa première visite, puis CONSERVÉ.
    @State private var builtTabs: Set<AppTab> = []

    /// La disposition compacte affichait `screen(for: model.selectedTab)`, un
    /// `switch` : changer d'onglet remplaçait donc le sous-arbre, et SwiftUI
    /// jetait tout l'état de l'écran quitté.
    ///
    /// Mesuré sur trois aller-retours carte ↔ actu : `loadModel()` de la carte
    /// s'exécutait 4 fois sur iPhone contre 1 seule sur iPad. Chacune de ces
    /// exécutions reconstruit deux `ContentStore`, un `MapModel` (requête
    /// SwiftData + filtrage des 537 points + requête des épingles) et un
    /// `CommunityModel`. C'était la lenteur propre à l'iPhone.
    ///
    /// Ce n'était pas qu'une affaire de vitesse : le zoom, le panoramique, la
    /// recherche et la position de défilement étaient perdus à chaque passage
    /// par un autre onglet.
    ///
    /// Les écrans masqués restent montés — c'est le prix de la conservation, et
    /// c'est exactement ce que fait déjà le `TabView` du régulier. Ils ne
    /// reçoivent ni touche ni lecture d'accessibilité.
    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    if builtTabs.contains(tab) {
                        screen(for: tab)
                            .opacity(tab == model.selectedTab ? 1 : 0)
                            .allowsHitTesting(tab == model.selectedTab)
                            .accessibilityHidden(tab != model.selectedTab)
                    }
                }
            }
            CompactTabBar(selection: $model.selectedTab)
        }
        .onChange(of: model.selectedTab, initial: true) { _, tab in
            builtTabs.insert(tab)
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
        let poiStore = ContentStore<POI>.live(
            collectionName: "poi",
            modelContext: modelContext
        )
        // Socle + overlay en cache, comme l'écran de progression : ce chemin ne
        // fait aucun réseau, mais il doit voir le même contenu, sinon le widget
        // affiche un pourcentage qui saute dès la première visite de l'onglet.
        let referenceStore = ContentStore<POI>.live(
            collectionName: "poi_gtav",
            seed: POILoader.bundled,
            modelContext: modelContext
        )
        let collectionStore = ContentStore<POICollection>.live(
            collectionName: "collections",
            seed: POICollectionLoader.bundled,
            modelContext: modelContext
        )
        _ = ProgressionModel(
            pois: poiStore.items + referenceStore.items,
            collections: collectionStore.items,
            trophies: [],
            modelContext: modelContext,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )

        // Le socle, comme pour la carte de référence : sans lui ce chemin ne voit
        // rien au premier lancement, et le widget annoncerait un favori absent
        // pendant que l'écran, lui, l'affiche.
        let cheatStore = ContentStore<Cheat>.live(
            collectionName: "cheats",
            seed: CheatLoader.bundled,
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
        case .social: SocialScreen()
        case .profile: ProfileScreen()
        }
    }
}
