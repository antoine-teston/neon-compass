import Foundation
import Supabase

/// Lit la vue matérialisée `leaderboard`.
///
/// Une lecture par ouverture d'onglet, quel que soit le nombre d'utilisateurs —
/// jamais une agrégation à la volée sur les profils. La vue est rafraîchie par
/// une tâche planifiée, exactement comme le document unique que
/// `rebuildLeaderboard` écrivait ; ce qui change, c'est qu'il n'y a plus de code
/// pour la produire, seulement une requête qui la définit.
final class SupabaseLeaderboardRepository: LeaderboardRepository {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func fetchWeekly() async throws -> Leaderboard? {
        guard let client else { return nil }
        let rows: [LeaderboardRow] = try await client
            .from("leaderboard")
            // `approvedCount` porte un nom camelCase côté Swift ; la colonne est
            // en snake_case. L'alias PostgREST fait le pont sans qu'on ait à
            // redéclarer une structure miroir juste pour renommer un champ.
            .select("uid,handle,xp,approvedCount:approved_count")
            .order("rank", ascending: true)
            .execute()
            .value

        // Vue vide = aucune reconstruction n'a encore tourné, ou personne n'a de
        // contribution approuvée. `nil` plutôt qu'un classement vide : l'écran
        // sait déjà ne rien afficher dans ce cas, et un tableau vide se lirait
        // comme « le classement existe et il est vide ».
        return rows.isEmpty ? nil : Leaderboard(rows: rows)
    }
}
