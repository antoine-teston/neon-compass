import Foundation

/// Ce qu'une inscription par e-mail produit.
///
/// Deux issues, et les confondre serait un mensonge à l'utilisateur : selon que
/// la confirmation d'e-mail est active ou non sur le projet, s'inscrire ouvre
/// une session **ou** n'ouvre rien du tout et envoie un lien. Un
/// `String?` laisserait le second cas se lire comme un échec.
enum EmailSignUpOutcome: Sendable, Equatable {
    /// Session ouverte immédiatement : la confirmation est désactivée.
    case signedIn(uid: String)
    /// Aucune session : un lien de confirmation vient de partir.
    case confirmationRequired
}

/// Abstraction sur l'authentification.
///
/// Trois entrées, et ce n'est pas un luxe : Apple est obligatoire dès qu'on
/// propose un autre fournisseur tiers (règle App Store 4.8), Google couvre ceux
/// qui n'ont pas d'appareil Apple ailleurs, et l'e-mail reste le seul chemin qui
/// ne dépend d'aucun tiers — donc le seul qui marche encore si l'un des deux
/// autres tombe.
protocol AuthProviding: Sendable {
    var currentUserID: String? { get }

    /// Sign in with Apple : le jeton signé par Apple et le nonce brut de CETTE
    /// tentative. L'aller-retour prouve que le jeton a été émis pour elle.
    func signIn(idTokenString: String, nonce: String) async throws -> String

    func signUp(email: String, password: String) async throws -> EmailSignUpOutcome
    func signIn(email: String, password: String) async throws -> String

    /// Google, par le flux OAuth du navigateur système. Rend l'identifiant
    /// d'utilisateur, comme les autres.
    func signInWithGoogle() async throws -> String

    /// Asynchrone parce que la déconnexion révoque la session côté serveur.
    /// La rendre synchrone obligerait à détacher cette révocation dans une
    /// tâche dont personne ne lit le résultat — un échec silencieux là où
    /// l'appelant a justement de quoi réagir.
    func signOut() async throws
}
