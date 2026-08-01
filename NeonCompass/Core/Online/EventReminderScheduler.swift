import Foundation

/// Quoi programmer, et quand. Aucune dépendance à `UserNotifications` : c'est
/// ce qui rend la règle testable sans jamais toucher au centre de notifications.
struct EventReminderScheduler: Sendable {
    /// Vingt-quatre heures avant la fin. Assez tôt pour agir, assez tard pour
    /// que ce soit une urgence — c'est tout l'intérêt du rappel.
    static let leadTime: TimeInterval = 86_400

    static func reminderDate(for event: OnlineEvent) -> Date {
        event.endsAt.addingTimeInterval(-leadTime)
    }

    /// Les rappels encore programmables, dans l'ordre des événements reçus.
    /// Un rappel déjà passé est écarté : le programmer ne déclencherait rien
    /// et encombrerait la file du système.
    static func reminders(for events: [OnlineEvent], at now: Date) -> [(id: String, fireAt: Date)] {
        events.compactMap { event in
            let fireAt = reminderDate(for: event)
            guard fireAt > now else { return nil }
            return (id: event.id, fireAt: fireAt)
        }
    }
}
