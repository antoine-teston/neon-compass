import SwiftUI
import SwiftData

/// L'onglet Social, en hub : héro « Cette semaine » paginé par jeu (VI
/// d'abord), module « À voter », tuile Classement, bannière en queue. Une
/// section sans contenu disparaît — la règle `showsGamePicker`, généralisée.
/// Lisible sans compte : le compte n'est demandé que pour voter ou figurer au
/// classement, jamais pour lire.
struct SocialScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @Environment(AuthModel.self) private var authModel
    @Environment(ProfileModel.self) private var profileModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var model: OnlineEventsModel?
    @State private var leaderboardRows: [LeaderboardRow] = []
    @State private var communityModel: CommunityModel?
    @State private var heroPinned = false
    @State private var showsLeaderboard = false

    private let leaderboardRepository: any LeaderboardRepository = SupabaseLeaderboardRepository()
    private let notifications: any LocalNotificationScheduling = SystemLocalNotificationScheduler()

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        // La tâche appartient à l'ÉCRAN, jamais au ProgressView : accrochée au
        // ProgressView elle s'annulerait elle-même dès que `model` est assigné.
        // Cf. FeedScreen, où ce défaut avait gardé le fil vide.
        .task { await loadModel() }
    }

    private func content(_ model: OnlineEventsModel) -> some View {
        // `.everyMinute` remplace la minuterie Combine d'avant : la sélection de
        // la semaine courante bascule à la minute, le rebours à la seconde vit
        // dans `NCCountdownDigits` (fiche) et le compact se contente du même pas.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let shown = shownEvent(model, at: now)
            let visibility = SocialHubVisibility(
                serverEnabled: serverFeatures.isEnabled,
                proposalCount: communityModel?.visibleSpots.count ?? 0,
                leaderboardRowCount: leaderboardRows.count,
                heroShowsEvent: shown != nil,
                isProEntitled: proEntitlementModel.isProEntitled
            )

            ScrollView {
                VStack(spacing: 20) {
                    heroSection(model, now: now)
                    if visibility.showsVoteModule, let communityModel {
                        VoteModule(communityModel: communityModel)
                    }
                    // Tuile orpheline en H1 : elle s'étire en pleine largeur.
                    // La grille à deux colonnes arrive avec la seconde tuile (H2).
                    if visibility.showsLeaderboardTile {
                        LeaderboardTile(
                            rows: leaderboardRows,
                            myRank: profileModel.profile?.rank,
                            onOpen: { showsLeaderboard = true }
                        )
                    }
                    // Écran de liste : la bannière s'y applique (spec §5), en
                    // queue de colonne, jamais sur un état vide.
                    if visibility.showsBanner {
                        BannerAdView()
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(20)
                // La barre d'onglets flotte au-dessus du contenu — même réserve
                // que le fil actu, que l'écran d'avant n'avait pas besoin de
                // poser parce qu'il était court.
                .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
            }
            .refreshable {
                await model.refresh()
                // Sans ça, une date de fin corrigée côté contenu ne bougerait le
                // rappel qu'au prochain lancement à froid.
                await scheduleReminders(for: model.events)
                await loadLeaderboard()
                await loadCommunity()
            }
            .overlay(alignment: .top) {
                if heroPinned, let shown, let remaining = shown.remaining(at: now) {
                    PinnedCountdownChip(game: shown.game, remaining: remaining)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .sheet(isPresented: $showsLeaderboard) {
                LeaderboardSheet(rows: leaderboardRows)
            }
        }
    }

    /// Ce que le héro montre pour le jeu sélectionné — la fenêtre active, sinon
    /// la dernière terminée (dite « terminé », jamais en cours).
    private func shownEvent(_ model: OnlineEventsModel, at now: Date) -> OnlineEvent? {
        model.currentEvent(at: now) ?? model.latestEvent()
    }

    @ViewBuilder
    private func heroSection(_ model: OnlineEventsModel, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("social.hub.thisWeek")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            if model.availableGames.isEmpty {
                emptyState
            } else {
                WeeklyHeroPager(model: model, now: now)
                    // Le frame du héro dans l'espace du scroll pilote
                    // l'épinglage ; le seuil est pur et testé (`HeroPinning`).
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .scrollView)
                    } action: { frame in
                        let pinned = HeroPinning.isPinned(heroFrame: frame, visibleTop: 0)
                        if pinned != heroPinned {
                            // Animer la COMMANDE, jamais la liste.
                            withAnimation(.easeInOut(duration: 0.2)) { heroPinned = pinned }
                        }
                    }
            }
        }
    }

    /// Rien de publié : on le dit, on n'invente pas une semaine.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("social.empty.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
            Text("social.empty.body")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func loadModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<OnlineEvent>.live(
            collectionName: "online_events",
            modelContext: modelContext
        )
        model = OnlineEventsModel(events: contentStore.items, contentStore: contentStore)
        try? await contentStore.syncIfNeeded()
        model?.update(events: contentStore.items)
        await scheduleReminders(for: contentStore.items)
        await loadLeaderboard()
        // Le module « À voter » est en première vue : son modèle se charge à
        // l'ouverture de l'écran, plus à la bascule d'un volet qui n'existe plus.
        await loadCommunity()
    }

    /// Garde du drapeau serveur : sans lui, ni vote ni classement — et pas de
    /// section vide non plus.
    private func loadCommunity() async {
        guard serverFeatures.isEnabled else { return }
        if communityModel == nil {
            communityModel = CommunityModel.live(modelContext: modelContext)
        }
        await communityModel?.loadApprovedSpots()
        if let uid = authModel.userID {
            await communityModel?.loadMyVotes(uid: uid)
        }
    }

    /// L'échec laisse la liste vide, et la tuile disparaît — état honnête,
    /// jamais un écran en erreur.
    private func loadLeaderboard() async {
        guard serverFeatures.isEnabled else { return }
        leaderboardRows = (try? await leaderboardRepository.fetchWeekly())?.rows ?? []
    }

    /// Reprogrammé à chaque synchronisation : un événement corrigé côté contenu
    /// doit déplacer son rappel, pas en ajouter un second. L'identifiant étant
    /// celui de l'événement, la reprogrammation remplace.
    private func scheduleReminders(for events: [OnlineEvent]) async {
        let pending = EventReminderScheduler.reminders(for: events, at: Date())
        guard !pending.isEmpty else { return }
        guard await notifications.requestPermissionIfNeeded() else { return }
        for reminder in pending {
            await notifications.schedule(
                id: reminder.id,
                title: String(localized: "social.reminder.title"),
                body: String(localized: "social.reminder.body"),
                at: reminder.fireAt
            )
        }
    }
}
