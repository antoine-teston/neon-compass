import Testing
import Foundation
@testable import NeonCompass

struct EventReminderSchedulerTests {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func event(id: String, endsAt: String) throws -> OnlineEvent {
        try JSONDecoder().decode(OnlineEvent.self, from: Data("""
        { "id": "\(id)", "game": "gtav", "startsAt": "2026-08-06T09:00:00Z",
          "endsAt": "\(endsAt)", "title": { "en": "x" } }
        """.utf8))
    }

    @Test func reminderFiresTwentyFourHoursBeforeTheEnd() throws {
        let event = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        #expect(EventReminderScheduler.reminderDate(for: event) == date("2026-08-12T09:00:00Z"))
    }

    /// Programmer dans le passé ne déclenche rien et encombre : un événement
    /// dont le rappel est déjà passé n'en reçoit pas.
    @Test func noReminderForAPastWindow() throws {
        let event = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        let reminders = EventReminderScheduler.reminders(for: [event], at: date("2026-08-12T18:00:00Z"))
        #expect(reminders.isEmpty)
    }

    @Test func noReminderForAnAlreadyFinishedEvent() throws {
        let event = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        let reminders = EventReminderScheduler.reminders(for: [event], at: date("2026-08-20T00:00:00Z"))
        #expect(reminders.isEmpty)
    }

    @Test func oneReminderPerFutureEvent() throws {
        let a = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        let b = try event(id: "online_b", endsAt: "2026-08-20T09:00:00Z")
        let reminders = EventReminderScheduler.reminders(for: [a, b], at: date("2026-08-06T12:00:00Z"))
        #expect(reminders.count == 2)
        #expect(reminders.map(\.id) == ["online_a", "online_b"])
    }

    /// L'identifiant de rappel est celui de l'événement : reprogrammer à la
    /// synchronisation suivante REMPLACE, ce qui interdit les doublons par
    /// construction plutôt que par un ménage explicite.
    @Test func reminderIdentifierIsTheEventIdentifier() throws {
        let event = try event(id: "online_a", endsAt: "2026-08-13T09:00:00Z")
        let reminders = EventReminderScheduler.reminders(for: [event], at: date("2026-08-06T12:00:00Z"))
        #expect(reminders.first?.id == "online_a")
    }
}
