import Foundation
import Supabase

/// Suppression de compte côté client, sans Edge Function.
///
/// **Chemin de repli, plus de chemin principal.** Il existait parce que la
/// cascade serveur exigeait le plan Blaze et n'était donc déployée nulle part
/// (`docs/ops/2026-07-27-sans-blaze.md`) ; les Edge Functions étant incluses
/// dans l'offre gratuite, `delete-account` redevient le chemin normal et fait
/// la cascade complète — anonymisation des contributions approuvées, suppression
/// des votes, du profil, puis du compte.
///
/// Ce repli reste utile pour un seul cas, celui d'avant le déploiement des
/// fonctions : le portail `backendFeaturesEnabled` est faux, l'app n'a que la
/// progression synchronisée à effacer, et l'obligation d'Apple — tout compte
/// créable dans l'app doit y être supprimable — ne souffre pas d'attendre.
///
/// Ce qu'il ne peut PAS faire, et qui est la raison pour laquelle il ne doit
/// pas devenir le chemin principal : supprimer le compte lui-même. Supabase
/// réserve `auth.admin.deleteUser` à `service_role`, une clé qui n'a rien à
/// faire dans un binaire distribué. Il efface donc les données et déconnecte,
/// puis délègue au serveur le jour où celui-ci existe.
final class SupabaseAccountDeletion: AccountDeleting {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func deleteAccount(uid: String) async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }

        // Un seul DELETE là où Firestore imposait de lire tous les documents
        // puis de les supprimer par lots de 500 — la limite d'un batch, qu'une
        // progression complète dépassait. RLS garantit qu'on n'efface que ses
        // propres lignes, donc le filtre `uid` est une ceinture, pas la
        // protection.
        try await client.from("progression").delete().eq("uid", value: uid).execute()

        try await client.auth.signOut()
    }
}
