import Foundation

/// Pourquoi un couple e-mail / mot de passe est refusé AVANT tout appel réseau.
///
/// Refuser localement ce que le serveur refusera de toute façon évite un
/// aller-retour et, surtout, permet de dire ce qui ne va pas dans la langue de
/// l'utilisateur — GoTrue répond en anglais et en termes d'API.
enum EmailCredentialProblem: Error, Equatable {
    case emptyEmail
    case malformedEmail
    case passwordTooShort(minimum: Int)
}

/// Validation pure d'un couple e-mail / mot de passe.
///
/// `enum` sans stockage, comme `AppleSignInCoordinator` : c'est la convention du
/// dépôt pour un espace de noms.
enum EmailCredential {
    /// Aligné sur le minimum par défaut de GoTrue. Le durcir ici sans le
    /// durcir côté projet donnerait une règle que rien ne fait respecter ;
    /// l'assouplir donnerait un refus serveur incompréhensible.
    static let minimumPasswordLength = 6

    /// Volontairement grossière. Valider une adresse e-mail par expression
    /// régulière est un problème sans solution correcte (la RFC 5322 autorise
    /// des formes que personne n'implémente) : la seule vérification qui vaille
    /// est l'envoi d'un message. On n'attrape donc ici que la faute de frappe
    /// évidente — pas d'arobase, pas de point après, un espace au milieu.
    static func validate(email: String, password: String) -> EmailCredentialProblem? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .emptyEmail }

        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        let looksLikeAnAddress = parts.count == 2
            && !parts[0].isEmpty
            && parts[1].contains(".")
            && !parts[1].hasPrefix(".")
            && !parts[1].hasSuffix(".")
            && !trimmed.contains(" ")
        if !looksLikeAnAddress { return .malformedEmail }

        if password.count < minimumPasswordLength {
            return .passwordTooShort(minimum: minimumPasswordLength)
        }
        return nil
    }

    /// L'adresse telle qu'elle doit partir : détourée et en minuscules.
    ///
    /// Sans ça, « Antoine@Example.com » et « antoine@example.com » créeraient
    /// deux comptes chez certains fournisseurs, et l'utilisateur ne
    /// comprendrait pas pourquoi sa progression a disparu.
    static func normalized(email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
