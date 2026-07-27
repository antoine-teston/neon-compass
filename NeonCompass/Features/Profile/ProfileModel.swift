import Foundation
import Observation

@Observable
@MainActor
final class ProfileModel {
    private(set) var profile: Profile?

    private let repository: ProfileRepository
    private let functions: AccountFunctionsCalling
    private let localDeletion: AccountDeleting

    init(
        repository: ProfileRepository,
        functions: AccountFunctionsCalling,
        localDeletion: AccountDeleting
    ) {
        self.repository = repository
        self.functions = functions
        self.localDeletion = localDeletion
    }

    func loadProfile(uid: String) async {
        profile = try? await repository.fetchProfile(uid: uid)
    }

    func regenerateHandle() async throws {
        let newHandle = try await functions.regenerateHandle()
        profile?.handle = newHandle
    }

    /// Cascade complète côté serveur — profil, votes, anonymisation des
    /// contributions approuvées.
    func deleteAccount() async throws {
        try await functions.deleteAccount()
    }

    /// Repli quand les Cloud Functions ne sont pas déployées : seule la
    /// progression synchronisée et le compte lui-même existent, et leur
    /// propriétaire peut les effacer. Voir `AccountDeleting`.
    func deleteAccountLocally(uid: String) async throws {
        try await localDeletion.deleteAccount(uid: uid)
    }
}
