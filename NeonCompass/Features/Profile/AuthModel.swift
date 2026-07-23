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

    func signOut() throws {
        try authProvider.signOut()
        userID = nil
    }
}
