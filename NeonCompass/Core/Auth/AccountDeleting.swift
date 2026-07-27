import Foundation

/// Suppression de compte sans Cloud Function.
///
/// L'obligation existe dès qu'on propose une connexion : Apple exige que tout
/// compte créable dans l'app y soit supprimable. `deleteAccount` (la Cloud
/// Function) fait la cascade complète — profil, votes, anonymisation des
/// contributions approuvées. Tant que Blaze n'est pas activé elle n'est
/// déployée nulle part, mais le périmètre à effacer est réduit d'autant :
/// sans profil ni contributions, il ne reste que la progression synchronisée
/// et le compte lui-même, tous deux effaçables par leur propriétaire sous les
/// règles existantes (`profiles/{uid}/progression` : `if request.auth.uid == uid`).
protocol AccountDeleting: Sendable {
    func deleteAccount(uid: String) async throws
}
