import Foundation
import Observation

/// Est-ce que la couche serveur événementielle existe aujourd'hui ?
///
/// Les Cloud Functions exigent le plan Blaze. Tant qu'il n'est pas activé, huit
/// Functions écrites et testées ne sont déployées nulle part : profil et pseudo
/// (`createUserProfile`), XP et niveaux, contributions, votes, signalements,
/// notifications de catégorie suivie. Les écrans qui en dépendent ne mèneraient
/// donc nulle part — mieux vaut ne pas les proposer que les proposer cassés.
///
/// **Le défaut est FERMÉ**, à l'inverse de `CommunityGateProviding` : ce dernier
/// est un coupe-circuit sur une capacité qui existe (on l'éteint en cas
/// d'abus), il échoue donc ouvert. Celui-ci décrit une capacité qui n'existe
/// pas encore, il doit échouer fermé — se tromper dans ce sens n'affiche rien,
/// se tromper dans l'autre affiche des écrans qui échouent.
///
/// Le jour où Blaze est activé et les Functions déployées, un seul paramètre
/// Remote Config rallume tout, sans mise à jour de l'app.
protocol ServerFeatureGateProviding: Sendable {
    func isEnabled() async throws -> Bool
}

@Observable
@MainActor
final class ServerFeaturesModel {
    /// Faux jusqu'à preuve du contraire, y compris pendant le premier
    /// rafraîchissement : l'app doit s'ouvrir sur l'état sûr.
    private(set) var isEnabled = false

    private let gate: ServerFeatureGateProviding

    init(gate: ServerFeatureGateProviding) {
        self.gate = gate
    }

    func refresh() async {
        isEnabled = (try? await gate.isEnabled()) ?? false
    }
}
