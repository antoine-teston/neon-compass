import SwiftUI

/// Barre iPhone : carte en bouton central proéminent, rendu à part des
/// autres items. Le centrage suppose un nombre IMPAIR d'onglets — la
/// fusion des Défis dans le Profil l'a ramené à quatre, donc décentré,
/// jusqu'à ce qu'un cinquième onglet le rétablisse. `AppTabTests` garde
/// cette invariante.
/// Sur iPad, RootView utilise la TabView système (sidebarAdaptable).
struct CompactTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                ForEach(AppTab.allCases) { tab in
                    if tab == .map {
                        mapButton
                    } else {
                        tabButton(tab)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 12)
    }

    private var mapButton: some View {
        Button {
            selection = .map
        } label: {
            Image(systemName: AppTab.map.systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
        }
        .glassEffect(.regular.tint(NCColor.sunsetMagenta.opacity(0.6)).interactive(), in: .circle)
        .offset(y: -12)
        .accessibilityLabel(Text(AppTab.map.titleKey))
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20))
                Text(tab.titleKey)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selection == tab ? NCColor.neonCyan : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular.interactive())
    }
}
