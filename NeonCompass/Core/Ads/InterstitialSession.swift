import Foundation

/// Le comptage des interstitiels d'une session — et surtout, la définition de
/// « session ».
///
/// **Le piège que ce type corrige.** Le plafond de la spec vaut « un par
/// session », et le compteur vivait en mémoire : la session, c'était donc la vie
/// du processus. Or le cas d'usage phare de l'iPad est la tablette posée à côté
/// de la télé toute la soirée — le processus ne meurt jamais, et « un par
/// session » devenait « un par jour ». Une session est ici une période au
/// premier plan, réarmée après un séjour d'au moins `resetThreshold` en
/// arrière-plan.
///
/// L'horloge est passée en paramètre plutôt que lue : tout est vérifiable sans
/// attendre cinq minutes, et le type reste pur.
struct InterstitialSession: Equatable, Sendable {
    /// Cinq minutes : la convention d'usage pour découper des sessions
    /// analytiques. Assez long pour qu'un aller-retour vers Messages ne réarme
    /// rien, assez court pour qu'une vraie pause compte.
    static let resetThreshold: TimeInterval = 5 * 60

    private(set) var shownCount = 0

    /// L'instant du dernier passage en arrière-plan, tant qu'il n'a pas été
    /// consommé par un retour.
    private var backgroundedAt: Date?

    init() {}

    mutating func recordShown() {
        shownCount += 1
    }

    mutating func didEnterBackground(at date: Date) {
        backgroundedAt = date
    }

    mutating func willEnterForeground(at date: Date) {
        // Consommé quoi qu'il arrive : un séjour ne vaut que pour le retour qui
        // le suit immédiatement. Sans ce `defer`, un second retour rejouerait le
        // même vieux séjour et réarmerait une session à peine commencée.
        defer { backgroundedAt = nil }
        guard let backgroundedAt else { return }
        guard date.timeIntervalSince(backgroundedAt) >= Self.resetThreshold else { return }
        shownCount = 0
    }
}
