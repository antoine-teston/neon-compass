import Foundation
import Supabase

/// Les trois écritures communautaires.
///
/// **Deux d'entre elles ne sont plus des appels HTTP.** Voter et signaler sont
/// devenus des RPC Postgres `security definer` : l'app appelle une fonction SQL
/// au lieu de faire un aller-retour vers un runtime qui aurait de toute façon
/// fini par écrire dans cette même base. Une latence en moins, un composant en
/// moins à déployer, et la validation vit au même endroit que la contrainte qui
/// la garantit.
///
/// Soumettre reste une Edge Function : elle lit le coupe-circuit, applique le
/// cooldown, filtre le vocabulaire et fait la déduplication géographique — assez
/// de logique pour mériter un vrai langage, et assez de sensibilité pour ne pas
/// vouloir la voir réécrite en PL/pgSQL.
final class SupabaseContributionFunctions: ContributionFunctionsCalling {
    private struct VoteCounts: Decodable {
        let upvotes: Int
        let downvotes: Int
    }

    private struct SubmitPayload: Encodable {
        let category: String
        let title: String
        let positionX: Double
        let positionY: Double
        let languageCode: String

        enum CodingKeys: String, CodingKey {
            case category
            case title
            case positionX = "position_x"
            case positionY = "position_y"
            case languageCode = "language_code"
        }
    }

    private struct CastVotePayload: Encodable {
        let spotId: String
        let voteDirection: String

        enum CodingKeys: String, CodingKey {
            case spotId = "spot_id"
            case voteDirection = "vote_direction"
        }
    }

    private struct ReportPayload: Encodable {
        let spotId: String
        let reportReason: String?

        enum CodingKeys: String, CodingKey {
            case spotId = "spot_id"
            case reportReason = "report_reason"
        }
    }

    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    /// Lève un `ContributionSubmissionError` et jamais l'erreur brute du SDK :
    /// c'est le panneau qui affiche le résultat, et il doit pouvoir choisir une
    /// phrase traduite. Les messages de l'Edge Function sont de l'anglais en dur.
    func submitContribution(
        category: POICategory,
        title: String,
        position: NormalizedPoint,
        languageCode: String
    ) async throws {
        guard let client else { throw ContributionSubmissionError.signedOut }
        do {
            try await client.functions.invoke(
                "submit-contribution",
                options: FunctionInvokeOptions(
                    body: SubmitPayload(
                        category: category.rawValue,
                        title: title,
                        positionX: position.x,
                        positionY: position.y,
                        languageCode: languageCode
                    )
                )
            )
        } catch let error as FunctionsError {
            // `relayError` n'a ni statut ni corps : la fonction n'a pas été
            // jointe, ce qui est une panne et non un refus.
            guard case .httpError(let code, let data) = error else {
                throw ContributionSubmissionError.failed
            }
            throw ContributionSubmissionError(status: code, body: data)
        } catch {
            throw ContributionSubmissionError.failed
        }
    }

    func castVote(spotId: String, direction: VoteDirection) async throws -> (upvotes: Int, downvotes: Int) {
        guard let client else { throw SupabaseAuthError.notConfigured }
        // La RPC rend une TABLE, donc une ligne : les compteurs à jour, relus
        // après que le trigger les a maintenus.
        let rows: [VoteCounts] = try await client
            .rpc("cast_vote", params: CastVotePayload(spotId: spotId, voteDirection: direction.rawValue))
            .execute()
            .value
        guard let counts = rows.first else { throw URLError(.cannotParseResponse) }
        return (counts.upvotes, counts.downvotes)
    }

    func reportContribution(spotId: String, reason: String?) async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }
        try await client
            .rpc("report_contribution", params: ReportPayload(spotId: spotId, reportReason: reason))
            .execute()
    }
}
