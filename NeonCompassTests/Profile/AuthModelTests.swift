import Testing
@testable import NeonCompass

@MainActor
struct AuthModelTests {
    @Test func startsSignedOutWhenNoCurrentUser() {
        let model = AuthModel(authProvider: FakeAuthProvider())
        #expect(model.userID == nil)
    }

    @Test func startsSignedInWhenAuthProviderHasACurrentUser() {
        let provider = FakeAuthProvider()
        provider.userIDToReturn = "existing-uid"
        let model = AuthModel(authProvider: provider)
        #expect(model.userID == "existing-uid")
    }

    @Test func signInSetsUserID() async throws {
        let model = AuthModel(authProvider: FakeAuthProvider())
        try await model.signIn(idTokenString: "token", nonce: "nonce")
        #expect(model.userID == "fake-uid")
    }

    @Test func signOutClearsUserID() async throws {
        let model = AuthModel(authProvider: FakeAuthProvider())
        try await model.signIn(idTokenString: "token", nonce: "nonce")
        try await model.signOut()
        #expect(model.userID == nil)
    }

    /// Une révocation qui échoue côté serveur ne doit PAS retenir
    /// l'utilisateur dans sa session : il vient de demander à en sortir, et le
    /// réseau n'est pas son problème. L'erreur remonte pour être signalée,
    /// elle n'annule pas la déconnexion locale.
    @Test func signOutClearsUserIDEvenWhenRevocationFails() async throws {
        let provider = FakeAuthProvider()
        provider.signOutError = FakeAuthProvider.Unreachable()
        let model = AuthModel(authProvider: provider)
        try await model.signIn(idTokenString: "token", nonce: "nonce")

        await #expect(throws: FakeAuthProvider.Unreachable.self) { try await model.signOut() }
        #expect(model.userID == nil)
    }
}
