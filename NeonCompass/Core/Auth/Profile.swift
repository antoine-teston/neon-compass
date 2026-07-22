import Foundation

/// Miroir du document `profiles/{uid}` écrit par la Cloud Function
/// `createUserProfile` — jamais écrit directement par le client (Security
/// Rules : write toujours refusé sur cette collection).
struct Profile: Codable, Equatable, Sendable {
    let handle: String
    let xp: Int
    let level: Int
    let isPremium: Bool
}
