import Foundation

/// Miroir (partiel) du document `contributions/{id}` — jamais écrit
/// directement par le client (Security Rules : write toujours refusé sur
/// cette collection, tout passe par les Cloud Functions submitContribution/
/// castVote/reportContribution). `createdAt` n'est volontairement pas
/// modélisé ici : ce plan n'affiche pas de date, et FirestoreContributionRepository
/// décode via document.data(as:), qui ignore silencieusement les champs non
/// déclarés — voir ce fichier pour pourquoi JSONSerialization est interdit
/// (Timestamp non sérialisable).
struct Contribution: Identifiable, Equatable, Sendable {
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
