import Foundation
import Supabase

/// Implémentation réelle de `AuthProviding`, adossée à Supabase Auth.
///
/// Sign in with Apple est le seul fournisseur proposé (spec §3). Le flux natif
/// prend l'`idToken` et le `nonce` que `AppleSignInCoordinator` produit déjà —
/// ce coordinateur ne change pas d'une ligne dans cette migration, c'est
/// exactement la même paire que Firebase consommait.
///
/// `currentUserID` est synchrone parce que le protocole l'exige, et Supabase
/// expose la session courante sans `await` une fois chargée. Avant ce
/// chargement, elle vaut nil — même comportement qu'avec Firebase, et les
/// appelants savent déjà traiter « pas encore connecté ».
final class SupabaseAuthProvider: AuthProviding {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    var currentUserID: String? {
        client?.auth.currentUser?.id.uuidString
    }

    func signIn(idTokenString: String, nonce: String) async throws -> String {
        guard let client else { throw SupabaseAuthError.notConfigured }
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idTokenString, nonce: nonce)
        )
        return session.user.id.uuidString
    }

    func signOut() async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }
        try await client.auth.signOut()
    }
}

enum SupabaseAuthError: Error {
    case notConfigured
}
