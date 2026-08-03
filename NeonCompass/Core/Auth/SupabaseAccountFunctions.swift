import Foundation
import Supabase

/// Implémentation réelle d'`AccountFunctionsCalling`, adossée aux Edge
/// Functions (miroir de `supabase/functions/regenerate-handle` et
/// `delete-account`).
///
/// Les Edge Functions sont incluses dans l'offre gratuite. C'est ce qui fait
/// disparaître le blocage documenté par `docs/ops/2026-07-27-sans-blaze.md` :
/// ces deux fonctions étaient écrites, testées, et déployées nulle part.
final class SupabaseAccountFunctions: AccountFunctionsCalling {
    private struct HandleResponse: Decodable {
        let handle: String
    }

    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func regenerateHandle() async throws -> String {
        guard let client else { throw SupabaseAuthError.notConfigured }
        let response: HandleResponse = try await client.functions
            .invoke("regenerate-handle")
        return response.handle
    }

    func deleteAccount() async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }
        try await client.functions.invoke("delete-account")
    }
}
