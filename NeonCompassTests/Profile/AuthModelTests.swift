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
        try model.signOut()
        #expect(model.userID == nil)
    }
}
