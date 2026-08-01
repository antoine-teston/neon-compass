import Foundation

/// Miroir du document `profiles/{uid}` écrit par la Cloud Function
/// `createUserProfile` — jamais écrit directement par le client (Security
/// Rules : write toujours refusé sur cette collection).
struct Profile: Codable, Equatable, Sendable {
    var handle: String
    let xp: Int
    let level: Int
    let isPremium: Bool
    /// Déposé par `rebuildLeaderboard`. Absent tant qu'elle n'a pas tourné —
    /// le Profil n'affiche alors pas de ligne de rang, plutôt qu'un zéro faux.
    let rank: Int?
}
