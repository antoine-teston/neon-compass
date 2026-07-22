import Foundation
import Observation

@Observable
@MainActor
final class ProfileModel {
    private(set) var profile: Profile?

    private let repository: ProfileRepository
    private let functions: AccountFunctionsCalling

    init(repository: ProfileRepository, functions: AccountFunctionsCalling) {
        self.repository = repository
        self.functions = functions
    }

    func loadProfile(uid: String) async {
        profile = try? await repository.fetchProfile(uid: uid)
    }

    func regenerateHandle() async throws {
        let newHandle = try await functions.regenerateHandle()
        profile?.handle = newHandle
    }

    func deleteAccount() async throws {
        try await functions.deleteAccount()
    }
}
