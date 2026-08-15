import Foundation
import Observation

@Observable
@MainActor
final class OnlineEventsModel {
    private(set) var events: [OnlineEvent]

    /// Le volet affiché. Initialisé sur un jeu qui a du contenu : ouvrir sur un
    /// volet vide alors que l'autre a un événement en cours serait absurde.
    var selectedGame: Game

    private let contentStore: ContentStore<OnlineEvent>?

    init(events: [OnlineEvent], contentStore: ContentStore<OnlineEvent>? = nil) {
        self.events = events
        self.contentStore = contentStore
        self.selectedGame = Self.defaultGame(for: events)
    }

    /// Jeux ayant au moins un événement, dans l'ordre de `Game`. Même règle que
    /// `ProgressionModel.gamesWithChallenges`.
    var availableGames: [Game] {
        Game.allCases.filter { game in events.contains { $0.game == game } }
    }

    /// Pas de sélecteur tant qu'il n'y a rien à choisir : tant que le mode en
    /// ligne à venir n'est pas ouvert, une seule entrée occuperait la place
    /// sans rien offrir.
    var showsGamePicker: Bool {
        availableGames.count > 1
    }

    /// L'événement dont la fenêtre contient `now`, pour le jeu affiché.
    /// `nil` hors de toute fenêtre — la vue dit alors « terminé » plutôt que de
    /// montrer le dernier comme s'il durait encore.
    ///
    /// **Le plus récemment COMMENCÉ gagne, et ce n'est pas un détail de tri.**
    /// Deux fenêtres peuvent se chevaucher : la source prolonge parfois un
    /// événement, ou publie une phase 2 qui empiète d'une heure sur la phase 1.
    /// `events` n'a aucun ordre garanti — il vient de `ContentMerge.merge`, pas
    /// d'un tri — donc un `first` rendait un résultat ARBITRAIRE, capable de
    /// changer d'une synchronisation à l'autre sans que la donnée bouge. Le
    /// compte à rebours affiché aurait été tiré au sort entre deux dates.
    ///
    /// Le départage est total : à début égal, la fin la plus tardive, puis l'`id`.
    /// Un ordre partiel laisserait exactement le même indéterminisme un cran plus
    /// bas.
    func currentEvent(at now: Date) -> OnlineEvent? {
        currentEvent(at: now, game: selectedGame)
    }

    /// La même fenêtre active, pour un jeu donné : chaque page du héro du hub
    /// interroge le sien, quelle que soit la page affichée.
    func currentEvent(at now: Date, game: Game) -> OnlineEvent? {
        events
            .filter { $0.game == game && $0.isActive(at: now) }
            .max { isEarlier($0, than: $1) }
    }

    /// Ordre total sur deux événements : début, puis fin, puis `id`.
    private func isEarlier(_ lhs: OnlineEvent, than rhs: OnlineEvent) -> Bool {
        if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
        if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
        return lhs.id < rhs.id
    }

    /// Le plus récent du jeu affiché, actif ou non. Sert à dire ce qui vient de
    /// se terminer, jamais à le faire passer pour en cours.
    ///
    /// Trié sur la FIN — c'est « ce qui vient de se terminer » qu'on cherche ici,
    /// pas « ce qui a commencé en dernier ». Départagé jusqu'au bout pour la même
    /// raison que `currentEvent(at:)` : à fin égale, un ordre partiel rendait un
    /// résultat arbitraire.
    func latestEvent() -> OnlineEvent? {
        latestEvent(game: selectedGame)
    }

    /// Le plus récent d'un jeu donné — même départage total que la version
    /// `selectedGame`, qui délègue ici.
    func latestEvent(game: Game) -> OnlineEvent? {
        events.filter { $0.game == game }.max { lhs, rhs in
            if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            return lhs.id < rhs.id
        }
    }

    func update(events newEvents: [OnlineEvent]) {
        let hadNothing = events.isEmpty
        events = newEvents
        // Ne réécrit la sélection que si elle n'avait pas pu être faite : un
        // utilisateur qui a choisi un volet ne doit pas le voir changer sous
        // ses yeux à la première synchronisation.
        if hadNothing {
            selectedGame = Self.defaultGame(for: newEvents)
        }
    }

    /// Tirer-pour-rafraîchir. L'échec est silencieux : le geste rend la main et
    /// l'écran garde ce qu'il affichait. Même choix que `FeedModel.refresh()`.
    func refresh() async {
        guard let contentStore else { return }
        try? await contentStore.refresh()
        update(events: contentStore.items)
    }

    private static func defaultGame(for events: [OnlineEvent]) -> Game {
        Game.allCases.first { game in events.contains { $0.game == game } } ?? .reference
    }
}
