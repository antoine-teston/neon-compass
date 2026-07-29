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
                    inputModePicker
                    TextField("cheats.search.placeholder", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: .capsule)

                    ForEach(model.sections, id: \.category) { section in
                        sectionHeader(section.category)
                        ForEach(section.cheats) { cheat in
                            if let code = cheat.codes[model.activeInputMode] {
                                CheatCard(
                                    cheat: cheat,
                                    code: code,
                                    isFavorite: model.isFavorite(cheat),
                                    onTap: { onSelect(cheat) },
                                    onToggleFavorite: { model.toggleFavorite(cheat) }
                                )
                            }
                        }
                    }

                    if !model.unavailableInActiveMode.isEmpty {
                        CheatsUnavailableGroup(
                            cheats: model.unavailableInActiveMode,
                            model: model,
                            onSelect: onSelect
                        )
                    }

                    footnote
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

    private func sectionHeader(_ category: CheatCategory) -> some View {
        Text(category.label)
            .font(NCTypography.cardMeta)
            .foregroundStyle(NCColor.sunsetOrange)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    /// Quatre segments : le mode se choisit une fois et se retient, il ne mérite
    /// pas plus de surface, mais il doit rester visible pour qu'on découvre
    /// qu'il y en a quatre. Les libellés sont les formes courtes ; VoiceOver
    /// annonce le nom complet.
    private var inputModePicker: some View {
        Picker("cheats.mode.picker", selection: $model.activeInputMode) {
            ForEach(CheatInputMode.allCases, id: \.self) { mode in
                Text(mode.shortLabel)
                    .tag(mode)
                    .accessibilityLabel(Text(mode.label))
            }
        }
        .pickerStyle(.segmented)
    }

    /// Une fois en pied de liste, pas trente-six fois sur les cartes : ce que
    /// l'utilisateur veut savoir des trophées, il veut le savoir une fois.
    private var footnote: some View {
        Text("cheats.footnote.safe")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }

    /// La réservation vient de `BannerAdView` lui-même, qui la définit à partir
    /// de la taille qu'il DEMANDE et qu'il clampe.
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
}
