import Foundation
import Supabase

/// Implémentation réelle de `ProfileRepository`.
///
/// Contrairement à Firestore, le profil existe **dès** la connexion : là où
/// `createUserProfile` était un déclencheur d'authentification asynchrone — d'où
/// la fenêtre documentée dans `submitContribution.ts` où le profil n'existait
/// pas encore juste après l'inscription — le trigger Postgres s'exécute dans la
/// même transaction que la création de l'utilisateur.
///
/// `nil` reste possible et reste traité : une ligne peut avoir été supprimée
/// entre-temps, et faire échouer l'écran Profil pour ça n'apprendrait rien à
/// personne.
final class SupabaseProfileRepository: ProfileRepository {
    /// Clés explicites : la table est en `snake_case` (convention Postgres),
    /// le modèle en `camelCase` (convention Swift), et aucune conversion
    /// automatique ne fait le pont correctement dans les deux sens.
    private struct Row: Decodable {
        let handle: String
        let xp: Int
        let level: Int
        let isPremium: Bool
        let rank: Int?

        enum CodingKeys: String, CodingKey {
            case handle
            case xp
            case level
            case isPremium = "is_premium"
            case rank
        }
    }

    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func fetchProfile(uid: String) async throws -> Profile? {
        guard let client else { return nil }
        let rows: [Row] = try await client
            .from("profiles")
            .select("handle,xp,level,is_premium,rank")
            .eq("uid", value: uid)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return Profile(handle: row.handle, xp: row.xp, level: row.level, isPremium: row.isPremium, rank: row.rank)
    }
}
