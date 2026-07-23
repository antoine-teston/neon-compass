@preconcurrency import FirebaseAuth

/// Implémentation réelle de AuthProviding. Ne référence jamais
/// FirebaseApp.configure() — la configuration de l'app reste centralisée
/// au niveau App.
final class FirebaseAuthProvider: AuthProviding {
    nonisolated(unsafe) private let auth: Auth

    init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }

    var currentUserID: String? {
        auth.currentUser?.uid
    }

    func signIn(idTokenString: String, nonce: String) async throws -> String {
        let credential = OAuthProvider.credential(providerID: .apple, idToken: idTokenString, rawNonce: nonce)
        let result = try await auth.signIn(with: credential)
        return result.user.uid
    }

    func signOut() throws {
        try auth.signOut()
    }
}
