import Foundation
import Supabase

/// Les contributions de l'utilisateur courant.
///
/// `fetchApproved` n'existe pas ici, et c'est délibéré : les spots approuvés
/// passent par les fragments publiés sur le CDN, pas par une lecture de table.
/// Cette requête-ci ne rend que les quelques contributions d'une personne, et
/// elle doit être fraîche — un contributeur doit voir sa soumission tout de
/// suite, sans attendre la prochaine reconstruction des fragments.
final class SupabaseContributionRepository: ContributionRepository {
    /// Clés explicites : la table est en `snake_case`, le modèle en `camelCase`.
    /// Et `position` est reconstruite depuis deux colonnes — la table stocke des
    /// scalaires plutôt qu'un objet imbriqué, ce qui rend la déduplication
    /// géographique indexable.
    private struct Row: Decodable {
        let id: String
        let authorUid: String?
        let authorHandle: String
        let category: POICategory
        let title: String
        let languageCode: String
        let positionX: Double
        let positionY: Double
        let status: Contribution.Status
        let upvotes: Int
        let downvotes: Int

        enum CodingKeys: String, CodingKey {
            case id
            case authorUid = "author_uid"
            case authorHandle = "author_handle"
            case category
            case title
            case languageCode = "language_code"
            case positionX = "position_x"
            case positionY = "position_y"
            case status
            case upvotes
            case downvotes
        }
    }

    private static let columns =
        "id,author_uid,author_handle,category,title,language_code,position_x,position_y,status,upvotes,downvotes"

    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func fetchMine(uid: String) async throws -> [Contribution] {
        guard let client else { return [] }
        let rows: [Row] = try await client
            .from("contributions")
            .select(Self.columns)
            .eq("author_uid", value: uid)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { row in
            Contribution(
                id: row.id,
                authorUid: row.authorUid,
                authorHandle: row.authorHandle,
                category: row.category,
                title: row.title,
                languageCode: row.languageCode,
                position: NormalizedPoint(x: row.positionX, y: row.positionY),
                status: row.status,
                upvotes: row.upvotes,
                downvotes: row.downvotes
            )
        }
    }

    private struct VoteRow: Decodable {
        let contributionId: String
        let direction: String

        enum CodingKeys: String, CodingKey {
            case contributionId = "contribution_id"
            case direction
        }
    }

    func fetchMyVotes(uid: String) async throws -> [String: VoteDirection] {
        guard let client else { return [:] }
        let rows: [VoteRow] = try await client
            .from("votes")
            .select("contribution_id,direction")
            .eq("uid", value: uid)
            .execute()
            .value
        // Une direction inconnue est ignorée plutôt que fatale : la contrainte
        // `check` de la table l'interdit, mais le jour où elle gagnerait une
        // troisième valeur, perdre une ligne vaut mieux que perdre la liste.
        return rows.reduce(into: [:]) { result, row in
            if let direction = VoteDirection(rawValue: row.direction) {
                result[row.contributionId] = direction
            }
        }
    }
}
