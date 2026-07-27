import Testing
@testable import NeonCompass

final class SpyAccountDeletion: AccountDeleting, @unchecked Sendable {
    private(set) var deletedUIDs: [String] = []
    var errorToThrow: Error?

    func deleteAccount(uid: String) async throws {
        deletedUIDs.append(uid)
        if let errorToThrow { throw errorToThrow }
    }
}

private struct DeletionRefused: Error {}

@MainActor
struct ProfileModelTests {
    @Test func loadProfileFetchesAndStoresTheProfile() async {
        let repository = FakeProfileRepository()
        repository.profileToReturn = Profile(handle: "NEON-FALCON-88", xp: 0, level: 0, isPremium: false)
        let model = ProfileModel(repository: repository, functions: FakeAccountFunctions(), localDeletion: SpyAccountDeletion())
        await model.loadProfile(uid: "some-uid")
        #expect(model.profile?.handle == "NEON-FALCON-88")
    }

    @Test func loadProfileLeavesProfileNilWhenNotYetCreated() async {
        let model = ProfileModel(repository: FakeProfileRepository(), functions: FakeAccountFunctions(), localDeletion: SpyAccountDeletion())
        await model.loadProfile(uid: "some-uid")
        #expect(model.profile == nil)
    }

    @Test func regenerateHandleUpdatesTheStoredProfile() async throws {
        let repository = FakeProfileRepository()
        repository.profileToReturn = Profile(handle: "NEON-FALCON-88", xp: 0, level: 0, isPremium: false)
        let functions = FakeAccountFunctions()
        functions.handleToReturn = "CHROME-MIRAGE-42"
        let model = ProfileModel(repository: repository, functions: functions, localDeletion: SpyAccountDeletion())
        await model.loadProfile(uid: "some-uid")

        try await model.regenerateHandle()

        #expect(model.profile?.handle == "CHROME-MIRAGE-42")
    }

    @Test func deleteAccountCallsTheFunctionExactlyOnce() async throws {
        let functions = FakeAccountFunctions()
        let model = ProfileModel(repository: FakeProfileRepository(), functions: functions, localDeletion: SpyAccountDeletion())
        try await model.deleteAccount()
        #expect(functions.deleteAccountCallCount == 1)
    }

    /// Sans Cloud Functions déployées, la suppression passe par le client — et
    /// ne doit surtout PAS appeler la Function, qui n'existe nulle part.
    @Test func localDeletionNeverTouchesTheCloudFunction() async throws {
        let functions = FakeAccountFunctions()
        let deletion = SpyAccountDeletion()
        let model = ProfileModel(repository: FakeProfileRepository(), functions: functions, localDeletion: deletion)

        try await model.deleteAccountLocally(uid: "some-uid")

        #expect(deletion.deletedUIDs == ["some-uid"])
        #expect(functions.deleteAccountCallCount == 0)
    }

    /// L'échec doit remonter : `user.delete()` refuse une session ancienne, et
    /// l'utilisateur doit l'apprendre plutôt que de croire son compte supprimé.
    @Test func localDeletionPropagatesItsFailure() async {
        let deletion = SpyAccountDeletion()
        deletion.errorToThrow = DeletionRefused()
        let model = ProfileModel(repository: FakeProfileRepository(), functions: FakeAccountFunctions(), localDeletion: deletion)

        await #expect(throws: DeletionRefused.self) {
            try await model.deleteAccountLocally(uid: "some-uid")
        }
    }
}
