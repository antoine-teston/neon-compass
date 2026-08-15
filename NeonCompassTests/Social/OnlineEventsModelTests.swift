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

    /// Deux fenêtres actives en même temps : la source prolonge parfois un
    /// événement, ou publie une phase qui empiète sur la précédente. `events` n'a
    /// aucun ordre garanti (`ContentMerge.merge`, pas un tri), donc un `first`
    /// rendait un résultat arbitraire — le compte à rebours aurait été tiré au
    /// sort. Le plus récemment COMMENCÉ gagne.
    @Test func overlappingWindowsResolveToTheMostRecentlyStarted() throws {
        let ancienne = try event(id: "online_a", startsAt: "2026-07-30T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let nouvelle = try event(id: "online_b", startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let instant = date("2026-08-10T00:00:00Z")

        // Les deux ordres d'arrivée doivent donner la MÊME réponse : c'est tout
        // l'objet du correctif.
        #expect(OnlineEventsModel(events: [ancienne, nouvelle]).currentEvent(at: instant)?.id == "online_b")
        #expect(OnlineEventsModel(events: [nouvelle, ancienne]).currentEvent(at: instant)?.id == "online_b")
    }

    /// À début égal, la fenêtre qui dure le plus longtemps l'emporte — c'est le cas
    /// d'une prolongation dont l'ancienne version traîne encore dans le lot.
    @Test func equalStartsResolveToTheLaterEnd() throws {
        let courte = try event(id: "online_a", startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let prolongée = try event(id: "online_b", startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-20T09:00:00Z")
        let instant = date("2026-08-10T00:00:00Z")

        #expect(OnlineEventsModel(events: [courte, prolongée]).currentEvent(at: instant)?.id == "online_b")
        #expect(OnlineEventsModel(events: [prolongée, courte]).currentEvent(at: instant)?.id == "online_b")
    }

    /// Deux fenêtres rigoureusement identiques ne devraient pas exister, mais si
    /// elles arrivent, la réponse doit rester la même d'une synchronisation à
    /// l'autre. L'`id` départage.
    @Test func identicalWindowsStillResolveDeterministically() throws {
        let a = try event(id: "online_a", startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let b = try event(id: "online_b", startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let instant = date("2026-08-10T00:00:00Z")

        #expect(OnlineEventsModel(events: [a, b]).currentEvent(at: instant)?.id == "online_b")
        #expect(OnlineEventsModel(events: [b, a]).currentEvent(at: instant)?.id == "online_b")
    }

    /// `latestEvent` cherche ce qui vient de SE TERMINER : il trie sur la fin, pas
    /// sur le début, et ne doit pas dériver vers l'ordre de `currentEvent`.
    @Test func latestEventSortsOnTheEndOfTheWindow() throws {
        let commencéeAvant = try event(id: "online_a", startsAt: "2026-07-30T09:00:00Z", endsAt: "2026-08-20T09:00:00Z")
        let commencéeAprès = try event(id: "online_b", startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [commencéeAprès, commencéeAvant])
        #expect(model.latestEvent()?.id == "online_a")
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

    /// Les variantes par-jeu ne dépendent pas de `selectedGame` : chaque page du
    /// héro interroge SON jeu, quelle que soit la page affichée.
    @Test func perGameQueriesIgnoreSelectedGame() throws {
        let vi = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-13T09:00:00Z", endsAt: "2026-08-20T09:00:00Z")
        let v = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [vi, v])
        model.selectedGame = .leonida
        #expect(model.currentEvent(at: date("2026-08-14T00:00:00Z"), game: .reference) == nil)
        #expect(model.latestEvent(game: .reference)?.id == "online_v")
        #expect(model.currentEvent(at: date("2026-08-14T00:00:00Z"), game: .leonida)?.id == "online_vi")
    }
}
