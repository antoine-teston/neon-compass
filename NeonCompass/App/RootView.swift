import GoogleMobileAds
import SwiftData
import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    /// Construit ICI et non dans l'écran : une Live Activity survit à la
    /// fermeture de l'app, et un contrôleur reconstruit à chaque bascule
    /// d'onglet perdrait la main sur celle qui tourne.
    @State private var liveActivity = FavoritesLiveActivityController()
    @State private var onboarding = OnboardingModel()
    @State private var authModel = AuthModel(authProvider: SupabaseAuthProvider())
    @State private var proEntitlementModel: ProEntitlementModel
    // Constructed with a reference to proEntitlementModel, so it can't be a
    // plain `@State private var x = ...` default (those can't reference
    // `self`/sibling properties) — built in `init()` instead.
    @State private var widgetSummaryCoordinator: WidgetSummaryCoordinator
    /// Même raison que ci-dessus : il lit l'abonnement, donc il ne peut pas être
    /// une valeur par défaut de `@State`.
    @State private var interstitialCoordinator: InterstitialCoordinator
    @State private var themeStore = ThemeStore()
    /// Le profil et la communauté vivaient dans `ProfileScreen`. Ils remontent
    /// ici parce que la feuille de réglages, elle, a quitté cet écran : ouverte
    /// depuis la molette de la barre haute, elle est joignable depuis l'Actu,
    /// les Codes et le Social, qui ne construisent pas le Profil.
    ///
    /// Conséquence assumée : pour un compte connecté, le profil est désormais
    /// chargé au lancement et non à la première visite du Profil. Ça corrige au
    /// passage une bizarrerie — « Mes propositions » ne se chargeait que si l'on
    /// passait par cet onglet.
    @State private var profileModel = ProfileModel(
        repository: SupabaseProfileRepository(),
        functions: SupabaseAccountFunctions(),
        localDeletion: SupabaseAccountDeletion()
    )
    /// Bâti à la connexion et pas au lancement : `CommunityModel.live` monte un
    /// `ContentStore`, et un compte déconnecté n'a rien à en faire.
    @State private var communityModel: CommunityModel?
    /// Faux par défaut : tant que les Edge Functions ne sont pas déployées, les
    /// écrans de compte et de communauté ne mènent nulle part. Une ligne de
    /// `app_config` les rallume tous d'un coup, sans mise à jour de l'app.
    @State private var serverFeatures = ServerFeaturesModel(gate: SupabaseServerFeatureGate())
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    /// Fourni par `NeonCompassApp`, qui le construit avant le premier rendu — cet
    /// écran ne fait que le retransmettre au chemin d'amorçage du widget.
    @Environment(FoundStore.self) private var foundStore
    /// La persistance du « vu » du point d'onglet Social.
    private let weekSeenStore: any WeekSeenStoring = UserDefaultsWeekSeenStore()

    init() {
        let proEntitlementModel = ProEntitlementModel(provider: StoreKitProProvider())
        _proEntitlementModel = State(initialValue: proEntitlementModel)
        _widgetSummaryCoordinator = State(initialValue: WidgetSummaryCoordinator(
            writer: AppGroupWidgetSummaryWriter(),
            proEntitlementModel: proEntitlementModel
        ))
        _interstitialCoordinator = State(initialValue: InterstitialCoordinator(
            isProEntitled: { proEntitlementModel.isProEntitled }
        ))
    }

    var body: some View {
        Group {
            if onboarding.needsDisclaimer {
                DisclaimerView { onboarding.acceptDisclaimer() }
            } else if onboarding.needsConsentPrompt {
                ProgressView()
                    .task { await onboarding.requestConsent() }
            } else if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        // ATTACHÉE AVANT LES `.environment` CI-DESSOUS, ET C'EST OBLIGATOIRE.
        //
        // Une feuille ne voit que l'environnement posé PLUS BAS qu'elle dans la
        // chaîne de modificateurs. Placée après, celle-ci plantait à chaque
        // ouverture : « Fatal error: No Observable object of type AuthModel
        // found », `SettingsScreen` lisant `AuthModel`, `ProEntitlementModel` et
        // `ServerFeaturesModel` dans l'environnement. Vu au simulateur — la
        // compilation ne dit rien, et la feuille de l'explication ATT, elle, y
        // survit parce qu'elle ne demande rien à l'environnement.
        //
        // La feuille vivait auparavant dans `ProfileScreen`, donc au cœur du
        // sous-arbre, et n'avait jamais eu ce problème.
        .sheet(isPresented: $model.showsSettings) {
            SettingsScreen(profileModel: profileModel, communityModel: communityModel)
                // Même motif que la feuille d'explication plus bas : le `.tint`
                // de cette vue est posé PLUS HAUT que ce `.sheet`, donc le
                // contenu de la feuille en sort et repart en bleu système.
                .tint(themeStore.selectedTheme.accent)
        }
        .environment(authModel)
        // Pour que le Profil puisse basculer sur la Carte depuis l'invitation
        // à contribuer : une contribution se pose sur la carte, pas ailleurs.
        .environment(model)
        .environment(proEntitlementModel)
        .environment(liveActivity)
        .environment(widgetSummaryCoordinator)
        .environment(themeStore)
        .environment(serverFeatures)
        .environment(interstitialCoordinator)
        .environment(profileModel)
        .environment(communityModel)
        .preferredColorScheme(.dark)
        // Makes the Pro theme picker's selection a real, app-wide effect:
        // the selected accent becomes the default tint for any control that
        // doesn't already have a more specific, explicit `.tint(...)` override
        // (e.g. the deliberate sunsetMagenta/neonCyan call sites elsewhere
        // stay as-is). `ThemeStore` is `@Observable`, so this recomputes
        // whenever `selectTheme(_:)` mutates `selectedTheme`.
        .tint(themeStore.selectedTheme.accent)
        // Le SDK démarre dès que le consentement UMP est résolu, SANS attendre
        // l'ATT. Sans autorisation il n'utilise simplement pas l'IDFA et sert du
        // contextuel : servir des publicités avant l'ATT est son fonctionnement
        // normal, pas un contournement. Attendre l'ATT — qui n'arrive plus qu'à
        // la deuxième session — repousserait toute la publicité avec lui, soit
        // l'inverse du but recherché.
        //
        // La porte du consentement reste obligatoire et non contournable
        // (spec §RGPD). Clé sur `needsConsentPrompt`, la dernière porte à
        // basculer, pour ne se déclencher qu'une fois.
        .task(id: onboarding.needsConsentPrompt) {
            guard !onboarding.needsDisclaimer, !onboarding.needsConsentPrompt else { return }
            await MobileAds.shared.start()
        }
        .task {
            // Compte cette session. Idempotent par processus : c'est ce compteur
            // qui décide que l'explication ATT n'arrive qu'au deuxième
            // lancement.
            onboarding.registerLaunch()
            // Seeds the widget with real data at launch, BEFORE the user ever
            // visits Progression/Cheats (those screens only construct their
            // models lazily on first appearance — see `WidgetSummaryCoordinator`'s
            // doc comment). Without this, a Pro user who adds the widget but
            // starts on the default Feed tab would see 0%/no-favorite-cheat
            // even if real `FoundEntry`/`FavoriteCheat` data already exists.
            // AVANT toute lecture : configure la source de contenu pour que la
            // première synchronisation parte déjà du bon côté. Sans réseau, la
            // valeur reste nil et tout retombe sur le socle embarqué et le
            // cache.
            await ContentSourceConfigurator.configureFromAppConfig()
            refreshSocialTabBadge()
            hydrateWidgetSummaryFromCache()
            await proEntitlementModel.refresh()
            await serverFeatures.refresh()
            await interstitialCoordinator.refreshFrequency()
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
        // Le plafond « un interstitiel par session » ne veut rien dire sans une
        // définition de session, et le processus ne meurt jamais sur l'iPad posé
        // à côté de la télé toute la soirée. Voir `InterstitialSession`.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: interstitialCoordinator.didEnterBackground()
            case .active: interstitialCoordinator.willEnterForeground()
            default: break
            }
        }
        // Une feuille et non une porte : l'app reste utilisable derrière, et
        // `requestTrackingAuthorization` a besoin que l'app soit ACTIVE — ce
        // qu'un écran de démarrage ne garantit pas, et son échec est silencieux.
        .onChange(of: onboarding.needsTrackingExplainer, initial: true) { _, needs in
            showsTrackingExplainer = needs
        }
        // L'accroche vit sur le GROUPE et non dans `compactLayout`, où elle
        // était née : les deux dispositions sélectionnent par le même
        // `model.selectedTab`, et l'iPad doit éteindre le point « nouvelle
        // semaine » comme l'iPhone — attachée au compact seul, le régulier
        // n'avait ni badge ni marquage vu.
        .onChange(of: model.selectedTab, initial: true) { _, tab in
            builtTabs.insert(tab)
            // Ouvrir le Social marque la semaine courante comme vue : le point
            // s'éteint et ne revient pas pour la même semaine.
            if tab == .social, let id = model.socialCurrentWeekID {
                weekSeenStore.markWeekSeen(id)
                model.socialTabShowsDot = false
            }
        }
        // Le profil suit le compte, pas l'onglet : voir la déclaration de
        // `profileModel`.
        .task(id: authModel.userID) {
            guard let userID = authModel.userID else { return }
            await profileModel.loadProfile(uid: userID)
            if communityModel == nil {
                communityModel = CommunityModel.live(modelContext: modelContext)
            }
            await communityModel?.loadMyContributions(uid: userID)
        }
        .sheet(isPresented: $showsTrackingExplainer) {
            TrackingExplainerView(
                onContinue: {
                    showsTrackingExplainer = false
                    Task { await onboarding.requestTrackingAuthorization() }
                },
                onLater: {
                    showsTrackingExplainer = false
                    onboarding.deferTrackingExplainer()
                }
            )
            // Le `.tint` de cette vue est posé PLUS HAUT dans la chaîne que ce
            // `.sheet` : le contenu de la feuille sort donc de sa portée et
            // repartait en bleu système, au milieu d'une app synthwave.
            // Constaté au simulateur, pas déduit.
            .tint(themeStore.selectedTheme.accent)
            // On ne referme pas d'un glissement : le choix se fait par l'un des
            // deux boutons, dont « Plus tard », qui n'engage à rien.
            .interactiveDismissDisabled()
        }
    }

    /// Piloté par `onboarding.needsTrackingExplainer`, mais distinct de lui :
    /// une feuille a besoin d'un binding qu'elle puisse remettre à faux
    /// elle-même, ce qu'une propriété calculée ne permet pas.
    @State private var showsTrackingExplainer = false

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
                        tabContent(for: tab)
                            .opacity(tab == model.selectedTab ? 1 : 0)
                            .allowsHitTesting(tab == model.selectedTab)
                            .accessibilityHidden(tab != model.selectedTab)
                    }
                }
            }
            CompactTabBar(selection: $model.selectedTab, showsSocialDot: model.socialTabShowsDot)
        }
    }

    private var regularLayout: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    tabContent(for: tab)
                } label: {
                    Label(tab.titleKey, systemImage: tab.systemImage)
                }
                // Le pendant du point de `CompactTabBar` : le `TabView` ne
                // prend pas de vue libre dans son libellé, le badge système
                // est son seul signal. Un point, jamais un compte — même
                // langage que le compact.
                .badge(tab == .social && model.socialTabShowsDot ? Text(verbatim: "●") : nil)
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
            found: foundStore,
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

    /// Le point de l'onglet Social, depuis le CACHE de contenu — même motif que
    /// `hydrateWidgetSummaryFromCache` : l'onglet Social n'est construit qu'à sa
    /// première visite, donc personne d'autre ne lirait cette collection avant.
    private func refreshSocialTabBadge() {
        let store = ContentStore<OnlineEvent>.live(
            collectionName: "online_events",
            modelContext: modelContext
        )
        let events = OnlineEventsModel(events: store.items)
        let shown = events.currentEvent(at: Date()) ?? events.latestEvent()
        model.socialCurrentWeekID = shown?.id
        // Déjà sur l'onglet quand le calcul aboutit (il attend le réseau) : la
        // semaine est sous les yeux, on la marque vue au lieu d'allumer un
        // point qui ne s'éteindrait qu'au prochain aller-retour. Vu au
        // simulateur, pas déduit.
        if model.selectedTab == .social, let id = shown?.id {
            weekSeenStore.markWeekSeen(id)
            model.socialTabShowsDot = false
            return
        }
        model.socialTabShowsDot = SocialTabBadge.showsDot(
            currentWeekID: shown?.id,
            lastSeenID: weekSeenStore.lastSeenWeekID()
        )
    }

    /// Un écran d'onglet, coiffé de la barre haute quand il en veut une.
    ///
    /// L'accroche est ICI et non dans `compactLayout` : les deux dispositions
    /// passent par cette fonction, donc la barre n'a besoin d'exister qu'une
    /// fois. Posée dans le `ZStack` du compact, elle aurait fallu la dupliquer
    /// côté `TabView`, où elle aurait en plus recouvert la barre latérale.
    ///
    /// `safeAreaPadding` et non `padding` : c'est ce qui fait descendre le
    /// contenu des `ScrollView` de chaque écran SANS décoller leurs fonds, qui
    /// ignorent la zone sûre. Aucun écran n'a donc à connaître la barre — à la
    /// différence de la réserve basse, que chacun pose encore à la main.
    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        if tab.showsHeaderBar {
            ZStack(alignment: .top) {
                screen(for: tab)
                    .safeAreaPadding(.top, NCLayout.headerBarClearance)
                AppHeaderBar(onOpenSettings: { model.showsSettings = true }) {
                    // Le seul écran qui pose quelque chose dans la barre. La
                    // bascule y tenait une ligne entière en tête de sa liste,
                    // pour deux chiffres romains.
                    if tab == .cheats {
                        GameSwitch(game: $model.activeGame)
                    }
                }
            }
        } else {
            screen(for: tab)
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedScreen()
        case .map: MapScreen()
        case .cheats: CheatsScreen(game: model.activeGame)
        case .social: SocialScreen()
        case .profile: ProfileScreen()
        }
    }
}
