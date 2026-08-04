import Foundation

/// Miroir (partiel) du document `contributions/{id}` — jamais écrit
/// directement par le client (Security Rules : write toujours refusé sur
/// cette collection, tout passe par les Cloud Functions submitContribution/
/// castVote/reportContribution). `createdAt` n'est volontairement pas
/// modélisé ici : ce plan n'affiche pas de date, et FirestoreContributionRepository
/// décode via document.data(as:), qui ignore silencieusement les champs non
/// déclarés — voir ce fichier pour pourquoi JSONSerialization est interdit
/// (Timestamp non sérialisable).
struct Contribution: Identifiable, Equatable, Sendable, Codable {
    enum Status: String, Codable, Sendable {
        case pending, approved, rejected
    }

    let id: String
    let authorUid: String?
    let authorHandle: String
    let category: POICategory
    let title: String
    let languageCode: String
    let position: NormalizedPoint
    let status: Status
    var upvotes: Int
    var downvotes: Int

    /// L'horodatage d'approbation, **en chaîne brute**, tel que le fragment le
    /// porte.
    ///
    /// En `String` et non en `Date`, et ce n'est pas un raccourci : tout le
    /// décodage de contenu passe par un `JSONDecoder()` nu
    /// (`ContentCDN.swift:112,155`), dont la stratégie par défaut est
    /// `.deferredToDate` — une chaîne ISO 8601 y échouerait. Configurer ce
    /// décodeur toucherait tous les types de contenu à la fois. `OnlineEvent`
    /// résout la même contrainte de la même façon, en parsant à la main.
    ///
    /// Optionnel, et c'est ce qui protège le mode hors ligne : un fragment mis
    /// en cache avant l'ajout de la colonne n'a pas la clé, et un champ
    /// obligatoire ferait échouer le décodage du fragment entier.
    ///
    /// `var` et non `let` : Swift ne donne de valeur par défaut dans
    /// l'initialiseur membre à membre qu'aux propriétés `var` optionnelles. En
    /// `let`, tous les sites de construction existants devraient passer `nil`
    /// explicitement.
    var approvedAt: String?

    /// La date parsée, ou nil si absente ou illisible.
    ///
    /// Une date illisible est ignorée plutôt que fatale — même règle que
    /// `OnlineEventBonus.until` : la perdre range la proposition en fin de
    /// section, elle ne fabrique pas un ordre faux.
    var approvedAtDate: Date? { Self.parseTimestamp(approvedAt) }

    /// Une fonction et non une constante : `ISO8601DateFormatter` n'est pas
    /// `Sendable`, et sous concurrence stricte une constante statique non isolée
    /// est refusée à la compilation. Même contrainte que `OnlineEvent`.
    ///
    /// Deux passes : Postgres sérialise un `timestamptz` avec des fractions de
    /// seconde, que le format par défaut d'`ISO8601DateFormatter` refuse.
    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }
}

/// Fait entrer les spots communautaires dans `ContentStore` — donc dans les
/// fragments, la garde de version et le cache SwiftData, hérités tels quels.
///
/// C'est ce qui sort la lecture des spots du « une lecture par document » :
/// `fetchApproved()` lisait toute la collection à chaque lancement, sans cache,
/// soit un coût égal à `utilisateurs × lancements × spots`. Voir
/// `docs/superpowers/specs/2026-07-27-community-bundles-design.md`.
///
/// Pas de pierre tombale : les fragments sont reconstruits intégralement à
/// chaque passe, donc retirer un spot suffit à le faire disparaître — même
/// raisonnement que pour les cheats et les guides (`ContentItem.isDeleted`).
extension Contribution: ContentItem {}
