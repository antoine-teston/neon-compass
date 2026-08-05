import Foundation

/// Tout ce que le panneau de soumission sait, et rien de plus : ni SwiftUI, ni
/// I/O, ni horloge.
///
/// Même parti que `ContributionSections` — le tri y était un type pur pour être
/// testable, le formulaire l'est ici pour la même raison. Ce qu'on y vérifie
/// sans lever d'écran : qu'un refus ne jette pas la saisie, qu'un cooldown
/// désarme puis réarme, et que déplacer l'épingle lève un doublon.
///
/// **`now` est toujours un paramètre, jamais lu en interne.** Convention déjà
/// posée par `hubToFact`, et c'est ce qui rend le cooldown vérifiable sans
/// attendre une minute.
struct ContributionPlacement: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case editing(ContributionSubmissionError?)
        case sending
        case confirmed
    }

    /// Miroir de `length(btrim(title)) between 1 and 280`
    /// (`20260802120000_initial_schema.sql:89`).
    static let maxTitleLength = 280
    /// Le compteur n'apparaît qu'à partir d'ici. Permanent, il serait du bruit
    /// sur un champ que personne n'approche ; il doit surgir quand il commence à
    /// compter.
    static let counterThreshold = 240

    /// Les trois entrées de l'utilisateur. Leurs `didSet` portent l'effacement
    /// des refus que le geste vient de lever — et c'est délibérément là, plutôt
    /// que dans des méthodes `moved`/`picked` qu'un appelant pourrait oublier au
    /// profit d'une affectation directe.
    var position: NormalizedPoint {
        didSet { clearIfLifted(by: .placement) }
    }

    var category: POICategory = .landmark {
        didSet { clearIfLifted(by: .placement) }
    }

    var title: String = "" {
        didSet { clearIfLifted(by: .wording) }
    }

    private(set) var phase: Phase = .editing(nil)

    /// Instant avant lequel l'envoi reste désarmé. Nourri par le 429 du serveur
    /// ET, dès l'ouverture, par le dernier envoi réussi connu localement.
    private(set) var retryAfter: Date?

    init(position: NormalizedPoint, lastSubmissionAt: Date? = nil) {
        self.position = position
        self.retryAfter = lastSubmissionAt?.addingTimeInterval(
            TimeInterval(ContributionSubmissionError.fallbackCooldownSeconds)
        )
    }

    // MARK: - Lecture

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Le refus affiché, ou nil. Nil hors saisie : un refus périmé ne doit pas
    /// rester à l'écran pendant qu'on renvoie.
    var error: ContributionSubmissionError? {
        if case .editing(let error) = phase { return error }
        return nil
    }

    var showsCounter: Bool { trimmedTitle.count >= Self.counterThreshold }

    /// Volontairement NON borné à 280 : on laisse dépasser et on le montre,
    /// plutôt que de tronquer la frappe en silence.
    var titleLength: Int { trimmedTitle.count }

    /// Secondes restantes, arrondies par EXCÈS — annoncer moins que l'attente
    /// réelle ferait échouer le renvoi sur le fil.
    func remainingCooldown(now: Date) -> Int? {
        guard let retryAfter else { return nil }
        let remaining = retryAfter.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return Int(remaining.rounded(.up))
    }

    func canSubmit(now: Date) -> Bool {
        guard case .editing(let error) = phase else { return false }
        // Deux refus ne se réessaient pas : renvoyer contre un coupe-circuit
        // fermé ne peut que rater, et un jeton expiré demande de se reconnecter.
        if error == .disabled || error == .signedOut { return false }
        guard remainingCooldown(now: now) == nil else { return false }
        return (1...Self.maxTitleLength).contains(titleLength)
    }

    // MARK: - Transitions

    mutating func beganSending() { phase = .sending }

    mutating func failed(with error: ContributionSubmissionError, now: Date) {
        phase = .editing(error)
        if case .cooldown(let seconds) = error {
            retryAfter = now.addingTimeInterval(TimeInterval(seconds))
        }
    }

    mutating func succeeded() { phase = .confirmed }

    // MARK: - Ce qu'un geste lève

    /// Ce qu'une modification est capable de rendre caduc.
    private enum Lift {
        /// Déplacer ou changer de catégorie : la déduplication est bornée à un
        /// rayon ET à une catégorie, donc l'un comme l'autre lève le doublon.
        case placement
        /// Retaper le titre : l'utilisateur fait exactement ce qu'on lui demande.
        case wording
    }

    private mutating func clearIfLifted(by lift: Lift) {
        guard case .editing(let error) = phase, let error else { return }
        let lifted: Bool = switch lift {
        case .placement: error == .duplicateNearby
        case .wording: error == .titleRejected
        }
        if lifted { phase = .editing(nil) }
    }
}
