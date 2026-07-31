import Testing
@testable import NeonCompass

@MainActor
struct SettingsModelTests {
    private func makeModel(
        functions: FakeAccountFunctions = FakeAccountFunctions(),
        localDeletion: FakeAccountDeleting = FakeAccountDeleting()
    ) -> (SettingsModel, FakeAccountFunctions, FakeAccountDeleting) {
        let profileModel = ProfileModel(
            repository: FakeProfileRepository(),
            functions: functions,
            localDeletion: localDeletion
        )
        return (SettingsModel(profileModel: profileModel), functions, localDeletion)
    }

    /// Serveur actif : la cascade complète (profil, votes, anonymisation des
    /// contributions approuvées) passe par la Cloud Function.
    @Test func serverEnabledUsesCloudCascade() async {
        let (model, functions, localDeletion) = makeModel()
        let ok = await model.deleteAccount(uid: "uid-1", serverEnabled: true)
        #expect(ok)
        #expect(functions.deleteAccountCallCount == 1)
        #expect(localDeletion.deleteAccountCallCount == 0)
    }

    /// Sans Cloud Functions déployées, l'obligation Apple demeure : le client
    /// efface ce qu'il peut atteindre — progression synchronisée et compte.
    @Test func serverDisabledFallsBackToLocalDeletion() async {
        let (model, functions, localDeletion) = makeModel()
        let ok = await model.deleteAccount(uid: "uid-1", serverEnabled: false)
        #expect(ok)
        #expect(functions.deleteAccountCallCount == 0)
        #expect(localDeletion.deleteAccountCallCount == 1)
    }

    /// `user.delete()` exige une connexion récente : l'échec le plus probable
    /// se répare en se reconnectant, et il doit donc être DIT.
    @Test func failureIsReported() async {
        let functions = FakeAccountFunctions()
        functions.shouldThrowOnDelete = true
        let (model, _, _) = makeModel(functions: functions)
        let ok = await model.deleteAccount(uid: "uid-1", serverEnabled: true)
        #expect(!ok)
        #expect(model.deletionFailed)
    }
}
