import Foundation

/// Abstraction sur Firebase Auth — Sign in with Apple est le seul
/// fournisseur proposé (spec §3 : "seule option de connexion proposée").
protocol AuthProviding: Sendable {
    var currentUserID: String? { get }
    func signIn(idTokenString: String, nonce: String) async throws -> String
    func signOut() throws
}
