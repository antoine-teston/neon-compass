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
