import Foundation
import Observation

/// Le seul morceau de logique des réglages : quel chemin de suppression suivre.
///
/// Le reste de l'écran (thème, icône, catégories suivies, blocages) délègue
/// directement à des stores déjà couverts par leurs propres tests. Ce choix-ci
/// n'appartient à aucun d'eux : il dépend de `ServerFeaturesModel`, que la vue
/// lui passe plutôt qu'il ne l'observe — un modèle testable ne va pas chercher
/// Remote Config tout seul.
@Observable
@MainActor
final class SettingsModel {
    private(set) var deletionFailed = false

    private let profileModel: ProfileModel

    init(profileModel: ProfileModel) {
        self.profileModel = profileModel
    }

    func dismissDeletionFailure() {
        deletionFailed = false
    }

    /// Rend `true` si la suppression a abouti. L'appelant enchaîne alors sur la
    /// déconnexion.
    func deleteAccount(uid: String, serverEnabled: Bool) async -> Bool {
        do {
            if serverEnabled {
                try await profileModel.deleteAccount()
            } else {
                try await profileModel.deleteAccountLocally(uid: uid)
            }
            return true
        } catch {
            deletionFailed = true
            return false
        }
    }
}
