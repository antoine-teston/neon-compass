import SwiftUI

/// Le choix d'habillage. Réservé aux Pro par son SITE D'APPEL — `SettingsScreen`
/// n'insère cette section que si l'abonnement est ouvert — et non par une garde
/// interne, ce qui explique qu'on ne trouve ici aucune mention de
/// `ProEntitlementModel`.
///
/// L'interrupteur d'icône alternée a disparu le 2026-08-19. Il mentait deux
/// fois : il visait `AppIcon-Neon`, qui n'a jamais existé dans aucun catalogue,
/// et sa valeur se relisait depuis `UIApplication.alternateIconName` — donc
/// l'activer le faisait revenir tout seul à l'arrêt sous les yeux de
/// l'utilisateur. L'icône suit désormais le thème, synchronisée par `RootView`,
/// et n'a plus de commande propre : un thème est un tout, pas deux réglages qui
/// peuvent se contredire.
struct SettingsAppearanceSection: View {
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { themeStore.selectedTheme },
                set: { themeStore.selectTheme($0) }
            )) {
                ForEach(NCTheme.allCases) { theme in
                    Text(theme.nameKey).tag(theme)
                }
            } label: {
                Text("profile.theme.title")
            }
            .pickerStyle(.menu)
        } header: {
            // Le violet de la rampe, la seule note froide de la famille chaude :
            // la charte n'a pas de bleu, et emprunter celui du système pour une
            // pastille ferait entrer une sixième couleur dans la palette.
            SettingsIconLabel(
                "settings.section.appearance",
                systemImage: "paintpalette.fill",
                tint: NCColor.sunsetViolet
            )
        } footer: {
            // Sans cette ligne, rien ne dit que le choix porte au-delà de la
            // teinte des contrôles — or c'est le fond, et lui seul, qui fait
            // exister le verre.
            Text("profile.theme.footer")
        }
    }
}
