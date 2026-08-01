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
    func currentEvent(at now: Date) -> OnlineEvent? {
        events.first { $0.game == selectedGame && $0.isActive(at: now) }
    }

    /// Le plus récent du jeu affiché, actif ou non. Sert à dire ce qui vient de
    /// se terminer, jamais à le faire passer pour en cours.
    func latestEvent() -> OnlineEvent? {
        events.filter { $0.game == selectedGame }.max { $0.endsAt < $1.endsAt }
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
