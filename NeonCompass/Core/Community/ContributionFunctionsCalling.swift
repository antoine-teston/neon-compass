import Foundation

enum VoteDirection: String, Sendable {
    case up, down
}

protocol ContributionFunctionsCalling: Sendable {
    func submitContribution(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws
    func castVote(spotId: String, direction: VoteDirection) async throws -> (upvotes: Int, downvotes: Int)
    func reportContribution(spotId: String, reason: String?) async throws
}
