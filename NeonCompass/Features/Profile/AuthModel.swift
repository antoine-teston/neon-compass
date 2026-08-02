import Foundation
import Observation

@Observable
@MainActor
final class AuthModel {
    private(set) var userID: String?

    private let authProvider: AuthProviding

    init(authProvider: AuthProviding) {
        self.authProvider = authProvider
        self.userID = authProvider.currentUserID
    }

    func signIn(idTokenString: String, nonce: String) async throws {
        userID = try await authProvider.signIn(idTokenString: idTokenString, nonce: nonce)
    }

    /// `userID` retombe à nil quoi qu'il arrive, y compris si la révocation
    /// côté serveur échoue : refuser de déconnecter localement parce que le
    /// réseau est tombé enfermerait l'utilisateur dans une session qu'il vient
    /// justement de demander à quitter. L'erreur est propagée pour être
    /// signalée, pas pour annuler la déconnexion.
    func signOut() async throws {
        defer { userID = nil }
        try await authProvider.signOut()
    }
}
