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
        #if DEBUG
        Self.describeToken(idTokenString)
        #endif
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idTokenString, nonce: nonce)
        )
        return session.user.id.uuidString
    }

    #if DEBUG
    /// Décrit la FORME du jeton, jamais son contenu utile.
    ///
    /// Un jeton d'identité est une créance : le journaliser en entier
    /// permettrait de se faire passer pour son porteur à qui lirait la console.
    /// Ce qu'on affiche ici — nombre de segments, en-tête décodé, émetteur et
    /// audience — suffit à distinguer les trois pannes qu'on peut avoir : un
    /// jeton qui n'est pas un JWT, un JWT dont l'audience n'est pas notre bundle
    /// ID, et un JWT correct refusé pour une autre raison.
    /// Écrit dans un fichier, pas sur la sortie standard.
    ///
    /// `print` va sur stdout, que le journal unifié ne capte pas et que
    /// `simctl launch --console-pty` lâche dès que l'app passe en arrière-plan —
    /// ce qui arrive systématiquement pendant une connexion Apple, puisque le
    /// système prend la main. Un diagnostic qu'on ne peut pas lire ne diagnostique
    /// rien.
    static func describeToken(_ token: String) {
        var lines: [String] = []
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        lines.append("jeton : \(token.count) caractères, \(segments.count) segment(s)")

        if segments.count != 3 {
            lines.append("→ ce n'est PAS un JWT. Début : \(token.prefix(32))")
        } else {
            for (name, index) in [("en-tête", 0), ("charge", 1)] {
                var base64 = String(segments[index])
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
                base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
                guard let data = Data(base64Encoded: base64),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    lines.append("→ \(name) indécodable")
                    continue
                }
                if index == 0 {
                    lines.append("→ \(name) : \(json)")
                } else {
                    lines.append("→ iss=\(json["iss"] ?? "?")")
                    lines.append("→ aud=\(json["aud"] ?? "?")")
                    lines.append("→ sub=\(json["sub"] != nil ? "présent" : "ABSENT")")
                    lines.append("→ nonce=\(json["nonce"] ?? "ABSENT")")
                }
            }
        }

        let url = URL.documentsDirectory.appending(path: "auth-diagnostic.txt")
        try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
    #endif

    // MARK: - E-mail

    func signUp(email: String, password: String) async throws -> EmailSignUpOutcome {
        guard let client else { throw SupabaseAuthError.notConfigured }
        let response = try await client.auth.signUp(
            email: EmailCredential.normalized(email: email),
            password: password
        )
        // Une session nulle n'est PAS un échec : c'est la confirmation d'e-mail
        // activée sur le projet. La traiter comme une erreur afficherait
        // « connexion impossible » à quelqu'un dont le compte vient d'être créé
        // et qui doit simplement relever ses messages.
        guard let session = response.session else { return .confirmationRequired }
        return .signedIn(uid: session.user.id.uuidString)
    }

    func signIn(email: String, password: String) async throws -> String {
        guard let client else { throw SupabaseAuthError.notConfigured }
        let session = try await client.auth.signIn(
            email: EmailCredential.normalized(email: email),
            password: password
        )
        return session.user.id.uuidString
    }

    // MARK: - Google

    /// Flux OAuth dans le navigateur système, sans SDK Google.
    ///
    /// `supabase-swift` porte `ASWebAuthenticationSession` lui-même : il n'y a
    /// ni dépendance à ajouter — le CLAUDE.md en exige une justification
    /// concrète, il n'y en a pas — ni délégué de présentation à écrire.
    ///
    /// La session s'affiche par-dessus l'app et lui rend la main sur le schéma
    /// d'URL déclaré. Ce schéma doit être connu des DEUX côtés : `CFBundleURLTypes`
    /// dans l'Info.plist, et la liste des URL de redirection autorisées du
    /// projet Supabase. Une seule des deux manquante, et le navigateur reste
    /// ouvert sur une page blanche.
    func signInWithGoogle() async throws -> String {
        guard let client else { throw SupabaseAuthError.notConfigured }
        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: Self.oauthRedirectURL
        ) { session in
            // Sans partage de cookies : l'utilisateur choisit son compte Google
            // à chaque fois. C'est le bon défaut sur un appareil qui peut être
            // partagé, et ça évite qu'une session Google oubliée reconnecte
            // silencieusement quelqu'un d'autre.
            session.prefersEphemeralWebBrowserSession = true
        }
        return session.user.id.uuidString
    }

    /// Doit rester identique au schéma déclaré dans
    /// `NeonCompass/Support/Info-Ads.plist` et dans les URL de redirection du
    /// projet Supabase. La valeur est dupliquée de part et d'autre d'une
    /// frontière que le compilateur ne voit pas — un test la fige.
    static let oauthRedirectURL = URL(string: "co.antoineteston.neoncompass://auth-callback")!

    // MARK: - Déconnexion

    func signOut() async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }
        try await client.auth.signOut()
    }
}

enum SupabaseAuthError: Error {
    case notConfigured
}
