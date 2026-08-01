import Testing
import Foundation
@testable import NeonCompass

@MainActor
struct OnlineEventsModelTests {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func event(
        id: String,
        game: Game = .reference,
        startsAt: String,
        endsAt: String
    ) throws -> OnlineEvent {
        try JSONDecoder().decode(OnlineEvent.self, from: Data("""
        {
          "id": "\(id)", "game": "\(game.rawValue)",
          "startsAt": "\(startsAt)", "endsAt": "\(endsAt)",
          "title": { "en": "\(id)" }
        }
        """.utf8))
    }

    @Test func currentEventIsTheOneInsideTheWindow() throws {
        let past = try event(id: "online_a", startsAt: "2026-07-30T09:00:00Z", endsAt: "2026-08-06T09:00:00Z")
        let now = try event(id: "online_b", startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [past, now])
        #expect(model.currentEvent(at: date("2026-08-10T00:00:00Z"))?.id == "online_b")
    }

    /// Hors de toute fenêtre, il n'y a pas d'événement courant — la vue dira
    /// « terminé », elle ne montrera pas le dernier comme s'il durait encore.
    @Test func noCurrentEventOutsideEveryWindow() throws {
        let past = try event(id: "online_a", startsAt: "2026-07-30T09:00:00Z", endsAt: "2026-08-06T09:00:00Z")
        let model = OnlineEventsModel(events: [past])
        #expect(model.currentEvent(at: date("2026-08-10T00:00:00Z")) == nil)
        #expect(model.latestEvent()?.id == "online_a")
    }

    /// Le jeu sélectionné filtre : les bonus du volet en ligne actuel ne se
    /// mélangent pas à ceux du volet à venir.
    @Test func currentEventRespectsSelectedGame() throws {
        let five = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let six = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [five, six])
        model.selectedGame = .leonida
        #expect(model.currentEvent(at: date("2026-08-10T00:00:00Z"))?.id == "online_vi")
    }

    /// Même règle que `gamesWithChallenges` : pas de sélecteur tant qu'il n'y a
    /// rien à choisir. Tant que le mode en ligne à venir n'est pas ouvert, un
    /// sélecteur à une entrée ne ferait qu'occuper la place.
    @Test func gamePickerIsHiddenWithASingleGame() throws {
        let five = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [five])
        #expect(!model.showsGamePicker)
        #expect(model.availableGames == [.reference])
    }

    @Test func gamePickerAppearsWithBothGames() throws {
        let five = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let six = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [five, six])
        #expect(model.showsGamePicker)
        #expect(model.availableGames == [.leonida, .reference])
    }

    /// Le jeu par défaut est celui qui a du contenu : ouvrir sur un volet vide
    /// alors que l'autre a un événement en cours serait absurde.
    @Test func defaultGameIsOneThatHasEvents() throws {
        let six = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [six])
        #expect(model.selectedGame == .leonida)
    }

    /// Une synchronisation qui arrive sur un modèle vide choisit le jeu par
    /// défaut : aucun choix n'avait pu être fait avant elle.
    @Test func updateChoosesDefaultGameWhenModelWasEmpty() throws {
        let six = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [])
        model.update(events: [six])
        #expect(model.selectedGame == .leonida)
    }

    /// Un modèle qui avait déjà des événements garde la sélection de
    /// l'utilisateur à la synchronisation suivante, même si le nouveau jeu de
    /// données ferait pencher le jeu par défaut vers l'autre volet : le volet
    /// affiché ne doit pas changer sous les yeux de quelqu'un qui venait d'en
    /// choisir un.
    @Test func updatePreservesSelectionWhenModelAlreadyHadEvents() throws {
        let five = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [five])
        model.selectedGame = .leonida
        let onlyReference = try event(id: "online_v2", game: .reference, startsAt: "2026-08-13T09:00:00Z", endsAt: "2026-08-20T09:00:00Z")
        model.update(events: [onlyReference])
        #expect(model.selectedGame == .leonida)
    }

    @Test func emptyModelHasNothingAndCrashesNowhere() {
        let model = OnlineEventsModel(events: [])
        #expect(model.currentEvent(at: date("2026-08-10T00:00:00Z")) == nil)
        #expect(model.latestEvent() == nil)
        #expect(!model.showsGamePicker)
    }
}
