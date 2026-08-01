import Foundation
import UserNotifications

/// Notifications programmées localement, sans serveur.
///
/// Distinct de `FollowedCategoryNotifying`, qui porte les topics FCM des
/// catégories suivies et est réservé au Pro. Le rappel d'événement est gratuit
/// (spec fondatrice §5 : « les notifications générales restent gratuites »),
/// donc il lui faut son propre chemin de demande d'autorisation.
protocol LocalNotificationScheduling: Sendable {
    func requestPermissionIfNeeded() async -> Bool
    func schedule(id: String, title: String, body: String, at fireDate: Date) async
    func cancel(ids: [String]) async
}

/// Implémentation `UserNotifications`. Aucun Firebase ici : ce rappel ne quitte
/// jamais l'appareil.
struct SystemLocalNotificationScheduler: LocalNotificationScheduling {
    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    func schedule(id: String, title: String, body: String, at fireDate: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        // Même identifiant que l'événement : une reprogrammation REMPLACE au
        // lieu d'empiler. C'est ce qui interdit les doublons par construction.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancel(ids: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
