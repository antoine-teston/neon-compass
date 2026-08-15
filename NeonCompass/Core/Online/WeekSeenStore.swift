import Foundation

/// « Une semaine pas encore vue » : l'identifiant de l'événement que le hub
/// montrerait, comparé au dernier marqué vu. Pur — la persistance est à côté.
enum SocialTabBadge {
    static func showsDot(currentWeekID: String?, lastSeenID: String?) -> Bool {
        guard let currentWeekID else { return false }
        return currentWeekID != lastSeenID
    }
}

/// La persistance du « vu ». Un protocole pour que les tests n'écrivent jamais
/// dans les vrais `UserDefaults`.
protocol WeekSeenStoring: Sendable {
    func lastSeenWeekID() -> String?
    func markWeekSeen(_ id: String)
}

struct UserDefaultsWeekSeenStore: WeekSeenStoring {
    private static let key = "socialLastSeenWeekID"

    func lastSeenWeekID() -> String? {
        UserDefaults.standard.string(forKey: Self.key)
    }

    func markWeekSeen(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.key)
    }
}
