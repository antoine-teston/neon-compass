import ActivityKit
import Foundation

/// Ce qu'une Live Activity des favoris porte sur l'écran verrouillé.
///
/// **Compilé DANS LES DEUX cibles** — l'app qui la démarre et l'extension qui la
/// dessine. C'est la contrainte d'ActivityKit : les deux côtés doivent voir le
/// même type. D'où l'absence de toute dépendance ici, `Cheat` compris : la
/// Live Activity ne transporte que du texte déjà résolu, dans la langue et le
/// mode de saisie du moment. Faire traverser le modèle du catalogue obligerait à
/// embarquer le contenu, le décodage et la localisation dans l'extension.
struct FavoritesActivityAttributes: ActivityAttributes {
    /// Fixé au démarrage. Le jeu ne change pas en cours d'activité — en changer
    /// revient à regarder d'autres favoris, donc à en démarrer une autre.
    let gameLabel: String

    struct ContentState: Codable, Hashable {
        /// Les cinq favoris, déjà mis en forme. Au plus cinq : c'est le plafond
        /// gratuit, et c'est aussi ce que l'écran verrouillé sait montrer.
        let entries: [Entry]

        /// Le mode de saisie affiché, en clair — « PS », « Clavier »… Sans lui,
        /// une suite de glyphes ne dit pas de quelle manette elle parle, et
        /// l'activité survit à un changement de mode dans l'app.
        let modeLabel: String
    }

    /// Une ligne : ce que fait la triche, et comment on la saisit.
    ///
    /// `code` est DÉJÀ rendu en texte — « ○ ○ L1 ○ » ou « 1-999-547-867 ». Les
    /// glyphes de manette de l'app sont des vues SwiftUI dessinées à la main ;
    /// les réutiliser demanderait de compiler tout leur module dans l'extension
    /// pour un gain nul à cette taille.
    struct Entry: Codable, Hashable, Identifiable {
        let id: String
        let effect: String
        /// `nil` quand le mode actif ne porte pas ce code — la ligne reste, et le
        /// dit. Même règle que la carte des favoris : masquer une information
        /// n'est pas une réponse.
        let code: String?
    }
}
