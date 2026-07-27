#if DEBUG
@preconcurrency import FirebaseAuth

/// Le chemin Firestore de l'éditeur est-il réellement utilisable ?
///
/// Deux conditions, et l'ordre compte : `Auth.auth()` plante d'une erreur
/// fatale non rattrapable si `FirebaseApp.configure()` n'a pas tourné, donc le
/// court-circuit du `&&` est ce qui protège l'appel.
///
/// La seconde condition est celle qui mord aujourd'hui : les règles réservent
/// `editor_drafts` à un UID, et il n'existe aucun compte tant que Sign in with
/// Apple n'est pas utilisable — ce qui demande l'adhésion payante au programme
/// développeur Apple. D'où le repli fichier.
enum EditorRemoteAvailability {
    static var isUsable: Bool {
        FirebaseAvailability.isConfigured && Auth.auth().currentUser != nil
    }
}
#endif
