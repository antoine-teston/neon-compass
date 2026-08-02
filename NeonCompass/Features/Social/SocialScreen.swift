import SwiftUI
import SwiftData
// `Timer.publish` vient de Combine, et SwiftUI ne le réexporte pas de façon
// fiable. Aucun autre fichier du dépôt n'importe Combine : c'est le premier.
import Combine

/// L'onglet Social. Lisible sans compte : c'est du contenu éditorial publié,
/// pas de l'UGC. Le compte n'est demandé qu'au palier B2, et seulement pour
/// FIGURER au classement, jamais pour le lire.
struct SocialScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @State private var model: OnlineEventsModel?
    @State private var leaderboardRows: [LeaderboardRow] = []
    private let leaderboardRepository: any LeaderboardRepository = SupabaseLeaderboardRepository()
    /// Réévalué chaque minute : sans ça le compte à rebours resterait figé sur
    /// la valeur qu'il avait à l'ouverture de l'onglet.
    @State private var now = Date()

    /// `@State`, comme `now` juste au-dessus : en disposition compacte, l'onglet
    /// reste monté et sa valeur de vue est reconstruite à chaque réévaluation
    /// du parent (changement d'onglet, ou tout autre changement d'état de
    /// `RootView`). Un simple `let` recréerait le pipeline Combine — et donc la
    /// minuterie — à chaque reconstruction au lieu de le laisser survivre.
    @State private var tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
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
        .onReceive(tick) { now = $0 }
    }

    private func content(_ model: OnlineEventsModel) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.showsGamePicker {
                    Picker(selection: Binding(
                        get: { model.selectedGame },
                        set: { model.selectedGame = $0 }
                    )) {
                        ForEach(model.availableGames) { game in
                            Text(game.shortLabel).tag(game)
                        }
                    } label: {
                        Text("social.game.picker")
                    }
                    .pickerStyle(.segmented)
                }

                let shown = model.currentEvent(at: now) ?? model.latestEvent()
                if let shown {
                    OnlineEventCard(event: shown, now: now)
                } else {
                    emptyState
                }
                if serverFeatures.isEnabled {
                    LeaderboardSection(rows: leaderboardRows)
                }
                // Écran de liste : la bannière s'y applique (spec §5), jamais
                // sur la carte en interaction. Posée DANS le défilement, en
                // queue de colonne — même motif que `GuidesListView`.
                //
                // Conditionnée à l'abonnement : le Pro se vend d'abord sur la
                // suppression des pubs. En afficher une à quelqu'un qui a payé
                // pour ne plus en voir est le pire retour possible.
                // ET une carte à montrer : vu au simulateur, l'écran du jour J
                // — aucun événement publié — affichait « rien pour l'instant »
                // suivi d'une publicité dans un écran par ailleurs vide. Ça se
                // lit « on n'a rien pour toi, voilà une pub ». La spec §5 pose
                // la bannière sur les écrans de LISTE ; un état vide n'en est
                // pas un.
                if shown != nil, !proEntitlementModel.isProEntitled {
                    BannerAdView()
                }
            }
            // Plafonnée pour l'iPad : vu au simulateur, la carte s'étirait sur
            // les 13 pouces, deux lignes centrées perdues dans la largeur. Une
            // colonne de lecture vaut mieux qu'une bande.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .refreshable {
            await model.refresh()
            // Sans ça, une date de fin corrigée côté contenu ne bougeait le
            // rappel qu'au prochain lancement à froid — cf. `loadModel()`,
            // seul autre appelant, gardé par `guard model == nil`.
            await scheduleReminders(for: model.events)
            await loadLeaderboard()
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
    }

    /// Une lecture, gardée par le drapeau serveur : sans Cloud Functions
    /// déployées, `leaderboards/weekly` n'existe pas et l'interroger ne
    /// produirait qu'une erreur silencieuse à chaque ouverture d'onglet.
    ///
    /// L'échec laisse la liste vide, et la section dit alors « aucun spot
    /// approuvé » — état honnête, jamais un écran en erreur.
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
