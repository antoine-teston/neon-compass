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

    func signOut() throws {
        signOutCallCount += 1
        userIDToReturn = nil
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
    @Test func authProviderTracksSignOutCalls() throws {
        let fake = FakeAuthProvider()
        fake.userIDToReturn = "existing-uid"
        try fake.signOut()
        #expect(fake.signOutCallCount == 1)
        #expect(fake.currentUserID == nil)
    }
}
