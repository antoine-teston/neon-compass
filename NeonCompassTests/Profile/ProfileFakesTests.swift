import Testing
@testable import NeonCompass

final class FakeAuthProvider: AuthProviding {
    nonisolated(unsafe) var userIDToReturn: String?
    nonisolated(unsafe) private(set) var signOutCallCount = 0

    var currentUserID: String? { userIDToReturn }

    func signIn(idTokenString: String, nonce: String) async throws -> String {
        let uid = "fake-uid"
        userIDToReturn = uid
        return uid
    }

    /// Erreur à lever à la déconnexion, pour exercer le cas où la révocation
    /// côté serveur échoue mais où la session locale doit tomber quand même.
    nonisolated(unsafe) var signOutError: (any Error)?

    /// Issue à rendre à l'inscription par e-mail. Les deux comptent : selon
    /// que la confirmation est active sur le projet, s'inscrire ouvre une
    /// session ou n'ouvre rien.
    nonisolated(unsafe) var signUpOutcome: EmailSignUpOutcome = .signedIn(uid: "fake-uid")
    nonisolated(unsafe) var googleUID = "fake-google-uid"

    struct Unreachable: Error {}

    func signUp(email: String, password: String) async throws -> EmailSignUpOutcome {
        if case .signedIn(let uid) = signUpOutcome { userIDToReturn = uid }
        return signUpOutcome
    }

    func signIn(email: String, password: String) async throws -> String {
        let uid = "fake-email-uid"
        userIDToReturn = uid
        return uid
    }

    func signInWithGoogle() async throws -> String {
        userIDToReturn = googleUID
        return googleUID
    }

    func signOut() async throws {
        signOutCallCount += 1
        userIDToReturn = nil
        if let signOutError { throw signOutError }
    }
}

final class FakeProfileRepository: ProfileRepository {
    nonisolated(unsafe) var profileToReturn: Profile?

    func fetchProfile(uid: String) async throws -> Profile? {
        profileToReturn
    }
}

final class FakeAccountFunctions: AccountFunctionsCalling {
    nonisolated(unsafe) var handleToReturn = "NEON-FALCON-88"
    nonisolated(unsafe) private(set) var deleteAccountCallCount = 0
    nonisolated(unsafe) var shouldThrowOnDelete = false

    struct Boom: Error {}

    func regenerateHandle() async throws -> String {
        handleToReturn
    }

    func deleteAccount() async throws {
        deleteAccountCallCount += 1
        if shouldThrowOnDelete { throw Boom() }
    }
}

final class FakeAccountDeleting: AccountDeleting {
    nonisolated(unsafe) private(set) var deleteAccountCallCount = 0

    func deleteAccount(uid: String) async throws {
        deleteAccountCallCount += 1
    }
}

struct ProfileFakesTests {
    @Test func authProviderTracksSignOutCalls() async throws {
        let fake = FakeAuthProvider()
        fake.userIDToReturn = "existing-uid"
        try await fake.signOut()
        #expect(fake.signOutCallCount == 1)
        #expect(fake.currentUserID == nil)
    }
}
