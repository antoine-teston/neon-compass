import Testing
@testable import NeonCompass

@MainActor
struct ProfileModelTests {
    @Test func loadProfileFetchesAndStoresTheProfile() async {
        let repository = FakeProfileRepository()
        repository.profileToReturn = Profile(handle: "NEON-FALCON-88", xp: 0, level: 0, isPremium: false)
        let model = ProfileModel(repository: repository, functions: FakeAccountFunctions())
        await model.loadProfile(uid: "some-uid")
        #expect(model.profile?.handle == "NEON-FALCON-88")
    }

    @Test func loadProfileLeavesProfileNilWhenNotYetCreated() async {
        let model = ProfileModel(repository: FakeProfileRepository(), functions: FakeAccountFunctions())
        await model.loadProfile(uid: "some-uid")
        #expect(model.profile == nil)
    }

    @Test func regenerateHandleUpdatesTheStoredProfile() async throws {
        let repository = FakeProfileRepository()
        repository.profileToReturn = Profile(handle: "NEON-FALCON-88", xp: 0, level: 0, isPremium: false)
        let functions = FakeAccountFunctions()
        functions.handleToReturn = "CHROME-MIRAGE-42"
        let model = ProfileModel(repository: repository, functions: functions)
        await model.loadProfile(uid: "some-uid")

        try await model.regenerateHandle()

        #expect(model.profile?.handle == "CHROME-MIRAGE-42")
    }

    @Test func deleteAccountCallsTheFunctionExactlyOnce() async throws {
        let functions = FakeAccountFunctions()
        let model = ProfileModel(repository: FakeProfileRepository(), functions: functions)
        try await model.deleteAccount()
        #expect(functions.deleteAccountCallCount == 1)
    }
}
