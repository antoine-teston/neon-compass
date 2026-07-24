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

    /// 110pt covers the tallest realistic `largeAnchoredAdaptiveBanner`
    /// result on a phone-width screen plus the bubble's own padding — the
    /// exact ad height is only known at runtime (it depends on device
    /// width), so this reserved-space constant is a deliberately
    /// conservative upper-bound estimate, not a measurement.
    private var bannerClearance: CGFloat {
        (sizeClass == .compact ? NCLayout.compactTabBarClearance : 0) + 110
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
