import Foundation

/// Ce que le serveur peut opposer à une soumission, en un type que le panneau
/// sait traduire.
///
/// Elle existe parce que `MapScreen` écrivait `try? await communityModel.submit(…)` :
/// les cinq refus de l'Edge Function y devenaient indiscernables du succès, et
/// la feuille se refermait sur un envoi qui n'avait pas eu lieu.
///
/// **Le `code` fait autorité, le statut n'est qu'un repli.** Les deux 400 de
/// `submit-contribution` — forme invalide et vocabulaire banni — n'appellent pas
/// la même phrase, et rien d'autre ne les distingue. Le repli existe pour le jour
/// où l'app parle à une fonction pas encore redéployée : le chemin reste
/// intelligible au lieu de tout écraser en « échec ».
enum ContributionSubmissionError: Error, Equatable, Sendable {
    /// Le cooldown de soumission. `retryAfter` en secondes.
    case cooldown(retryAfter: Int)
    /// Un lieu de la MÊME catégorie existe à moins de `DEDUP_THRESHOLD_NORMALIZED`.
    /// Déplacer l'épingle ou changer de catégorie lève l'un comme l'autre ce refus.
    case duplicateNearby
    /// Vocabulaire banni. Le seul refus qui mérite « reformulez ».
    case titleRejected
    case signedOut
    /// Le coupe-circuit communautaire est fermé.
    case disabled
    /// Panne, réseau, corps illisible — et la forme invalide, qui ne peut venir
    /// que d'un défaut à nous.
    case failed

    /// Le repli du 429 quand le serveur ne chiffre pas l'attente. Doit rester
    /// égal à `COOLDOWN_SECONDS` de `supabase/functions/_shared/contribution.ts`.
    static let fallbackCooldownSeconds = 60

    /// Lit `{ error, code, retryAfter }`.
    init(status: Int, body: Data?) {
        let payload = body.flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }

        switch payload?.code {
        case "cooldown":
            self = .cooldown(retryAfter: payload?.retryAfter ?? Self.fallbackCooldownSeconds)
        case "duplicate":
            self = .duplicateNearby
        case "vocabulary":
            self = .titleRejected
        case "disabled":
            self = .disabled
        // `invalid` REJOINT le repli plutôt que d'accuser le titre : la longueur
        // est bornée côté client et les positions sont normalisées par
        // construction, donc ce refus signale un défaut chez nous. « Reformulez »
        // serait un mauvais conseil sur un titre qui n'a rien de fautif.
        default:
            switch status {
            case 401: self = .signedOut
            case 409: self = .duplicateNearby
            case 429: self = .cooldown(retryAfter: payload?.retryAfter ?? Self.fallbackCooldownSeconds)
            case 503: self = .disabled
            default: self = .failed
            }
        }
    }

    private struct Payload: Decodable {
        let code: String?
        let retryAfter: Int?
    }
}
