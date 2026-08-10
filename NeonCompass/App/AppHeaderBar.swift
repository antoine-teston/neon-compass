import SwiftUI

/// La barre haute : le mot-marque à gauche, un emplacement d'écran, les réglages
/// à droite.
///
/// Symétrique de `CompactTabBar` en bas — des capsules de verre qui flottent
/// au-dessus du contenu, dimensionnées à ce qu'elles portent. `RootView`
/// l'empile au-dessus de chaque écran qui la réclame.
///
/// **La molette reste ancrée à l'extrême droite, et rien ne passe après elle.**
/// C'était jusqu'ici la seule chose admise de ce côté, au motif qu'une barre dont
/// le côté droit changerait d'un onglet à l'autre cesserait d'être un repère. La
/// règle est révisée le 2026-08-10, et voici ce qui la remplace : **ce qui est
/// ancré, c'est la molette, pas le vide à sa gauche.** Un écran peut glisser un
/// contrôle dans `accessory`, entre le mot-marque et elle ; la molette ne bouge
/// pas d'un point, donc le geste appris — « les réglages sont dans le coin » —
/// tient toujours.
///
/// Ce que la règle continue d'interdire : déplacer la molette, la remplacer, ou
/// poser dans `accessory` autre chose qu'un contrôle qui commande l'écran qu'elle
/// surplombe. Le premier usage est la bascule de jeu de l'écran Codes, qui tenait
/// une ligne entière en tête de sa liste.
struct AppHeaderBar<Accessory: View>: View {
    let onOpenSettings: () -> Void
    @ViewBuilder var accessory: Accessory

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
                    // Le mot-marque cède AVANT tout le reste. Il est le seul
                    // élément de la barre dont la largeur soit négociable : la
                    // molette a sa cible de 44 points, et un contrôle d'écran
                    // n'est pas là pour décorer. En pratique il ne cède pas —
                    // mesuré, tout tient sur un iPhone 17 — mais la règle vaut
                    // pour les langues qui allongent et les corps de texte
                    // agrandis.
                    .layoutPriority(-1)

                Spacer(minLength: 0)

                accessory

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

extension AppHeaderBar where Accessory == EmptyView {
    /// La barre nue, pour les écrans qui n'ont rien à y poser.
    init(onOpenSettings: @escaping () -> Void) {
        self.init(onOpenSettings: onOpenSettings) { EmptyView() }
    }
}
