import Foundation
import Observation

@Observable
@MainActor
final class AuthModel {
    private(set) var userID: String?

    /// Vrai quand une inscription par e-mail attend une confirmation. Ce n'est
    /// ni un succès ni un échec : l'écran doit dire d'aller relever ses
    /// messages, et surtout ne pas prétendre que la connexion a réussi.
    private(set) var awaitingEmailConfirmation = false

    private let authProvider: AuthProviding

    init(authProvider: AuthProviding) {
        self.authProvider = authProvider
        self.userID = authProvider.currentUserID
    }

    func signIn(idTokenString: String, nonce: String) async throws {
        userID = try await authProvider.signIn(idTokenString: idTokenString, nonce: nonce)
        awaitingEmailConfirmation = false
    }

    func signInWithGoogle() async throws {
        userID = try await authProvider.signInWithGoogle()
        awaitingEmailConfirmation = false
    }

    /// Valide AVANT d'appeler le réseau : le serveur refuserait de toute façon,
    /// mais en anglais et en termes d'API.
    func signUp(email: String, password: String) async throws {
        if let problem = EmailCredential.validate(email: email, password: password) { throw problem }
        switch try await authProvider.signUp(email: email, password: password) {
        case .signedIn(let uid):
            userID = uid
            awaitingEmailConfirmation = false
        case .confirmationRequired:
            awaitingEmailConfirmation = true
        }
    }

    func signIn(email: String, password: String) async throws {
        if let problem = EmailCredential.validate(email: email, password: password) { throw problem }
        userID = try await authProvider.signIn(email: email, password: password)
        awaitingEmailConfirmation = false
    }

    /// `userID` retombe à nil quoi qu'il arrive, y compris si la révocation
    /// côté serveur échoue : refuser de déconnecter localement parce que le
    /// réseau est tombé enfermerait l'utilisateur dans une session qu'il vient
    /// justement de demander à quitter. L'erreur est propagée pour être
    /// signalée, pas pour annuler la déconnexion.
    func signOut() async throws {
        defer {
            userID = nil
            awaitingEmailConfirmation = false
        }
        try await authProvider.signOut()
    }
}
