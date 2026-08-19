import SwiftUI
import UIKit

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

            // La ligne n'apparaît QUE si l'app déclare des icônes alternatives.
            // Aucune n'est déclarée aujourd'hui (`AppIcon-Neon` reste à
            // produire, cf. docs/ops/2026-07-23-alternate-app-icons.md), et la
            // bascule no-oppait donc en silence — un `Toggle` qui revient tout
            // seul, ce qu'un `Form` rend encore plus visible. Elle réapparaîtra
            // d'elle-même le jour où l'asset est livré : rien à recoder.
            if UIApplication.shared.supportsAlternateIcons {
                Toggle("profile.icon.title", isOn: Binding(
                    get: { UIApplication.shared.alternateIconName != nil },
                    set: { themeStore.setAlternateIcon(named: $0 ? Self.neonIconName : nil) }
                ))
            }
        } header: {
            // Le violet de la rampe, la seule note froide de la famille chaude :
            // la charte n'a pas de bleu, et emprunter celui du système pour une
            // pastille ferait entrer une sixième couleur dans la palette.
            SettingsIconLabel(
                "settings.section.appearance",
                systemImage: "paintpalette.fill",
                tint: NCColor.sunsetViolet
            )
        }
    }

    private static let neonIconName = "AppIcon-Neon"
}
