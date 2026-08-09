import SwiftUI

/// La barre haute : le mot-marque à gauche, les réglages à droite.
///
/// Symétrique de `CompactTabBar` en bas — des capsules de verre qui flottent
/// au-dessus du contenu, dimensionnées à ce qu'elles portent. `RootView`
/// l'empile au-dessus de chaque écran qui la réclame ; elle ne sait rien de
/// l'onglet courant et n'a donc aucune raison de changer d'un écran à l'autre.
///
/// **La molette est la seule chose admise à droite**, et c'est ce qui la rend
/// utile : une barre dont le côté droit changerait d'un onglet à l'autre
/// cesserait d'être un repère. Elle y est parce que les réglages ne sont
/// l'affaire d'aucun écran en particulier — ils étaient jusqu'ici enfermés dans
/// l'entête du Profil, qu'il fallait donc atteindre pour changer une préférence
/// de notifications ou d'icône.
struct AppHeaderBar: View {
    let onOpenSettings: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                NCWordmark()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    // Purement décoratif : le nom de l'app n'apprend rien à qui
                    // l'a ouverte, et VoiceOver le rencontrerait avant le
                    // contenu de chaque écran.
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        // Blanche et non cyan : posée sur quatre écrans sur
                        // cinq, elle dépenserait sinon un accent lumineux
                        // partout, pour une commande qui n'est pas le sujet de
                        // l'écran qu'elle surplombe.
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                // Sans « plain », le bouton teinte son glyphe de la couleur
                // d'accentuation du thème.
                .buttonStyle(.plain)
                .accessibilityLabel(Text("settings.title"))
            }
        }
        .padding(.horizontal, 12)
    }
}
