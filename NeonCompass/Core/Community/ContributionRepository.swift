import Foundation

protocol ContributionRepository: Sendable {
    func fetchApproved() async throws -> [Contribution]
    func fetchMine(uid: String) async throws -> [Contribution]
}
