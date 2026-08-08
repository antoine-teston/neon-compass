import SwiftUI

/// La barre haute : le mot-marque, et rien d'autre.
///
/// Symétrique de `CompactTabBar` en bas — une capsule de verre qui flotte
/// au-dessus du contenu, dimensionnée à ce qu'elle porte. `RootView` l'empile
/// au-dessus de chaque écran qui la réclame ; elle ne sait rien de l'onglet
/// courant et n'a donc aucune raison de changer d'un écran à l'autre.
///
/// Elle est volontairement vide à droite. Tout ce qui serait tentant d'y poser —
/// réglages, recherche, bascule de jeu — vit déjà dans le contenu de l'écran
/// concerné, et une barre qui change de contenu d'un onglet à l'autre cesse
/// d'être un repère.
struct AppHeaderBar: View {
    var body: some View {
        NCWordmark()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            // Alignée à gauche, comme un logo d'en-tête : centrée, elle se
            // lirait comme un titre d'écran.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            // Purement décorative : le nom de l'app n'apprend rien à qui l'a
            // ouverte, et VoiceOver le rencontrerait avant le contenu de chaque
            // écran.
            .accessibilityHidden(true)
    }
}
