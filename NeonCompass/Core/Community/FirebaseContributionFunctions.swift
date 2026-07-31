import Foundation
@preconcurrency import FirebaseFunctions

/// Implémentation réelle de ContributionFunctionsCalling, région
/// europe-west1 (miroir de functions/src/submitContribution.ts,
/// castVote.ts, reportContribution.ts).
final class FirebaseContributionFunctions: ContributionFunctionsCalling {
    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "europe-west1")) {
        self.functions = functions
    }

    func submitContribution(category: POICategory, title: String, position: NormalizedPoint, languageCode: String) async throws {
        _ = try await functions.httpsCallable("submitContribution").call([
            "category": category.rawValue,
            "title": title,
            "position": ["x": position.x, "y": position.y],
            "languageCode": languageCode,
        ])
    }

    func castVote(spotId: String, direction: VoteDirection) async throws -> (upvotes: Int, downvotes: Int) {
        let result = try await functions.httpsCallable("castVote").call([
            "spotId": spotId,
            "direction": direction.rawValue,
        ])
        guard let data = result.data as? [String: Any],
              let upvotes = data["upvotes"] as? Int,
              let downvotes = data["downvotes"] as? Int else {
            throw URLError(.cannotParseResponse)
        }
        return (upvotes, downvotes)
    }

    func reportContribution(spotId: String, reason: String?) async throws {
        var payload: [String: Any] = ["spotId": spotId]
        if let reason {
            payload["reason"] = reason
        }
        _ = try await functions.httpsCallable("reportContribution").call(payload)
    }
}
