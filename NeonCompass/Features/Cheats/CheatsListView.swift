import SwiftUI

struct CheatsListView: View {
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                inputModePicker
                searchRow
                CheatsFilterBar(
                    categories: model.availableCategories,
                    selectedCategory: model.selectedCategory,
                    onSelect: { model.selectCategory($0) }
                )
                // La rangée reprend ses propres marges à l'intérieur de son
                // défilement, pour que les puces glissent bord à bord.
                .padding(.horizontal, -16)

                let flatIndex = model.flatIndexByID
                ForEach(model.sections, id: \.category) { section in
                    // L'en-tête disparaît quand une rubrique est choisie : la
                    // puce allumée dit déjà laquelle, et le répéter au-dessus
                    // d'une liste qui ne contient qu'elle n'apprend rien.
                    if model.selectedCategory == nil {
                        sectionHeader(section.category)
                    }
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
                        if showsInlineAd(after: flatIndex[cheat.id]) {
                            inlineAd
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
            // La barre d'onglets flotte au-dessus du contenu : sans cette
            // réserve, la dernière carte finirait dessous. Elle ne dépend pas de
            // Pro — la barre est là pour tout le monde.
            .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    /// La recherche et la bascule de jeu partagent une ligne : le sélecteur tenait
    /// une ligne à lui seul pour deux chiffres romains, au prix d'autant de
    /// hauteur perdue en haut d'un écran fait pour trouver un code vite.
    private var searchRow: some View {
        HStack(spacing: 10) {
            TextField("cheats.search.placeholder", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .padding(12)
                .glassEffect(.regular, in: .capsule)
            GameSwitch(game: $model.activeGame)
        }
    }

    /// Les positions viennent du modèle. La vue n'ajoute que la condition qui ne
    /// dépend pas du contenu, l'abonnement — comme dans le fil d'actu.
    private func showsInlineAd(after index: Int?) -> Bool {
        guard !proEntitlementModel.isProEntitled, let index else { return false }
        return model.adPositions.contains(index)
    }

    /// Même gabarit qu'une carte — mêmes marges, même rayon, même verre, et une
    /// annonce dimensionnée pour remplir ce gabarit plutôt qu'une bande fine
    /// perdue dedans. Un encart d'une autre taille dans une colonne de cartes
    /// casse le rythme de lecture.
    private var inlineAd: some View {
        BannerAdView(maxHeight: BannerAdView.cardSlotHeight)
            .frame(maxWidth: .infinity)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
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
}
