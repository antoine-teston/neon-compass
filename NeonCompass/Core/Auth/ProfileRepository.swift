import Foundation

protocol ProfileRepository: Sendable {
    func fetchProfile(uid: String) async throws -> Profile?
}
