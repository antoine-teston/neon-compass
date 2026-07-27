import SwiftUI

struct CheatsListView: View {
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 12) {
                    platformToggle
                    TextField("cheats.search.placeholder", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: .capsule)

                    ForEach(model.filteredCheats) { cheat in
                        CheatCard(
                            cheat: cheat,
                            platform: model.activePlatform,
                            isFavorite: model.isFavorite(cheat),
                            onTap: { onSelect(cheat) },
                            onToggleFavorite: { model.toggleFavorite(cheat) }
                        )
                    }
                }
                .padding(16)
                .padding(.bottom, proEntitlementModel.isProEntitled ? 0 : bannerClearance)
            }
            if !proEntitlementModel.isProEntitled {
                adBanner
            }
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    /// La réservation vient désormais de `BannerAdView` lui-même, qui la définit
    /// à partir de la taille qu'il DEMANDE et qu'il clampe. La constante de 150
    /// qui vivait ici se décrivait comme « une estimation haute délibérément
    /// conservatrice, pas une mesure » — et elle était fausse de 50 pt, autant
    /// de contenu perdu à chaque écran.
    private var bannerClearance: CGFloat {
        (sizeClass == .compact ? NCLayout.compactTabBarClearance : 0) + BannerAdView.reservedHeight
    }

    private var adBanner: some View {
        BannerAdView()
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
    }

    private var platformToggle: some View {
        Picker("cheats.platform.picker", selection: $model.activePlatform) {
            Text("cheats.platform.ps5").tag(Platform.ps5)
            Text("cheats.platform.xbox").tag(Platform.xbox)
        }
        .pickerStyle(.segmented)
    }
}
