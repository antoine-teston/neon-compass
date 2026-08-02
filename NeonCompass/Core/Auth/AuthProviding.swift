import Foundation

/// Abstraction sur Firebase Auth — Sign in with Apple est le seul
/// fournisseur proposé (spec §3 : "seule option de connexion proposée").
protocol AuthProviding: Sendable {
    var currentUserID: String? { get }
    func signIn(idTokenString: String, nonce: String) async throws -> String

    /// Asynchrone parce que la déconnexion révoque la session côté serveur.
    /// La rendre synchrone obligerait à détacher cette révocation dans une
    /// tâche dont personne ne lit le résultat — un échec silencieux là où
    /// l'appelant a justement de quoi réagir.
    func signOut() async throws
}
