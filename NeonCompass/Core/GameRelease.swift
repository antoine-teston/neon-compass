import Foundation

/// La date de sortie du jeu, et ce que l'app en montre.
///
/// Le type ne nomme jamais le jeu — ni ici, ni dans les chaînes qu'il pilote.
/// La marque reste interdite dans la prose que nous écrivons (`CLAUDE.md`), et
/// `Game.shortLabel` applique déjà la même règle avec ses chiffres romains nus.
enum GameRelease {
    /// 19 novembre 2026.
    ///
    /// Constante compilée, délibérément. La faire venir d'`app_config` aurait
    /// coûté une clé et un repli — pour un gain douteux : le cache d'`app_config`
    /// n'a pas de TTL, donc une correction n'agirait qu'au prochain lancement à
    /// froid, et un report de sortie s'annonce des mois à l'avance, ce qui laisse
    /// tout le temps à une soumission de passer la review.
    static let dayComponents = DateComponents(year: 2026, month: 11, day: 19)

    /// Sept jours. Passé ce délai, la carte de sortie se retire d'elle-même
    /// plutôt que de rester en tête du fil jusqu'à la fin des temps.
    static let releasedWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Minuit LOCAL.
    ///
    /// Une sortie mondiale se vit à l'heure du joueur, pas à celle d'un fuseau
    /// que personne n'habite. Le calendrier est un paramètre pour que les bornes
    /// soient testables sans dépendre de l'horloge ni du fuseau de la machine.
    ///
    /// Le repli sur `.distantFuture` n'est pas atteignable avec un calendrier
    /// grégorien — il existe pour que la fonction reste totale, et il échoue du
    /// bon côté : un rebours qui ne finit jamais plutôt qu'une sortie annoncée en
    /// 1970.
    static func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: dayComponents) ?? .distantFuture
    }

    /// Ce que l'app doit montrer à un instant donné.
    enum Phase: Equatable, Sendable {
        /// Avant la sortie. La valeur associée est le temps restant, en secondes.
        case countdown(TimeInterval)
        /// Le jour J et les six suivants.
        case released
        /// Au-delà. Plus rien à afficher.
        case gone
    }

    static func phase(at now: Date, calendar: Calendar = .current) -> Phase {
        let remaining = date(in: calendar).timeIntervalSince(now)
        // À la seconde exacte de la sortie, on est SORTI : un rebours qui
        // afficherait « 0j 0h 0m 0s » serait le seul moment où il ment.
        guard remaining > 0 else {
            return -remaining < releasedWindow ? .released : .gone
        }
        return .countdown(remaining)
    }
}
