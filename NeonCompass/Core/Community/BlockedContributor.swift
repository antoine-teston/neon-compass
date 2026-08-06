import Foundation
import SwiftData

/// Blocage strictement local (Apple 1.2 — "masquer tous les spots d'un
/// contributeur" est une liste locale, réversible, gérable dans les
/// réglages — jamais envoyée au serveur).
@Model
final class BlockedContributor {
    @Attribute(.unique) var authorUid: String
    var blockedAt: Date

    /// Enregistré au blocage, parce qu'on ne pourra plus le retrouver ensuite :
    /// la politique RLS de `profiles` est `using (auth.uid() = uid)`, donc le
    /// client ne lit que sa propre ligne. Sans lui, les réglages n'avaient que
    /// l'UUID brut à afficher. Optionnel pour que les lignes existantes migrent
    /// sans conversion — elles retombent sur l'UID tronqué.
    var authorHandle: String?

    init(authorUid: String, handle: String? = nil, blockedAt: Date = .now) {
        self.authorUid = authorUid
        self.authorHandle = handle
        self.blockedAt = blockedAt
    }
}
