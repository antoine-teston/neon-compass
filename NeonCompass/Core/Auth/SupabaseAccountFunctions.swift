import Foundation
import Supabase

/// Implémentation réelle d'`AccountFunctionsCalling`, adossée à l'Edge
/// Function (miroir de `supabase/functions/delete-account`).
///
/// Les Edge Functions sont incluses dans l'offre gratuite. C'est ce qui fait
/// disparaître le blocage documenté par `docs/ops/2026-07-27-sans-blaze.md` :
/// cette fonction était écrite, testée, et déployée nulle part.
final class SupabaseAccountFunctions: AccountFunctionsCalling {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func deleteAccount() async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }
        try await client.functions.invoke("delete-account")
    }
}
