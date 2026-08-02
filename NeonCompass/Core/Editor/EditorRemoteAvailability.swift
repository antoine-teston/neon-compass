#if DEBUG
/// Le chemin distant de l'éditeur est-il réellement utilisable ?
///
/// Deux conditions : un projet configuré, et une session ouverte. La seconde est
/// celle qui mord — RLS réserve `editor_drafts` aux comptes inscrits dans
/// `editors`, et il n'existe aucun compte tant que Sign in with Apple n'est pas
/// utilisable, ce qui demande l'adhésion payante au programme développeur Apple.
/// D'où le repli fichier.
///
/// L'ordre des conditions n'a plus l'importance qu'il avait : `Auth.auth()`
/// plantait d'une erreur fatale non rattrapable si Firebase n'était pas
/// configuré, et le court-circuit du `&&` était ce qui protégeait l'appel.
/// `SupabaseClientProvider.shared` rend simplement nil.
enum EditorRemoteAvailability {
    static var isUsable: Bool {
        SupabaseClientProvider.shared?.auth.currentUser != nil
    }
}
#endif
