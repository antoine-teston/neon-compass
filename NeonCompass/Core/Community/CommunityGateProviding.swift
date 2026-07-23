import Foundation

/// Abstraction over the Remote Config kill-switch — mirrors
/// ContentVersionProviding's pattern (Core/Content). A missing/unset
/// parameter is treated as enabled (fail-open for a feature that's
/// supplementary, not core — spec §"Contributions utilisateurs": "jamais
/// le plan A du démarrage").
protocol CommunityGateProviding: Sendable {
    func isEnabled() async throws -> Bool
}
