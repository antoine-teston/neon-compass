import Foundation
import SwiftData

/// Blocage strictement local (Apple 1.2 — "masquer tous les spots d'un
/// contributeur" est une liste locale, réversible, gérable dans les
/// réglages — jamais envoyée au serveur).
@Model
final class BlockedContributor {
    @Attribute(.unique) var authorUid: String
    var blockedAt: Date

    init(authorUid: String, blockedAt: Date = .now) {
        self.authorUid = authorUid
        self.blockedAt = blockedAt
    }
}
