import SwiftUI

struct CheatsListView: View {
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Le panneau de rubriques est-il déployé ?
    ///
    /// État de VUE, pas de modèle : rien ne l'écrit dans `UserDefaults`, donc il
    /// ne survit pas à un relancement. Il survit en revanche à un changement
    /// d'onglet, `RootView` gardant ses écrans vivants dans un `ZStack`.
    @State private var showCategories = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                // Les trois commandes suivent l'entonnoir : quel jeu, comment on
                // saisit, quoi chercher. Elles étaient dans l'ordre inverse du
                // plus large au plus étroit, et la bascule de jeu — qui remplace
                // tout le contenu de l'écran — voisinait avec le champ de
                // recherche sans hiérarchie qui dise lequel des deux compte.
                gameRow
                inputModePicker
                searchAndCategories

                let flatIndex = model.flatIndexByID
                ForEach(model.sections, id: \.category) { section in
                    // L'en-tête s'effaçait sous filtre, au motif que la puce
                    // allumée disait déjà laquelle. La puce vit désormais derrière
                    // l'entonnoir et n'est plus visible par défaut : la prémisse
                    // tombe, la condition avec elle. Le faire dépendre de
                    // `showCategories` le ferait clignoter à chaque ouverture du
                    // panneau — c'est pourquoi il est là inconditionnellement.
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

    /// La bascule de jeu, seule et centrée.
    ///
    /// Centrée parce que cet écran n'a pas de titre — `RootView` n'accorde de
    /// barre de navigation à aucun écran d'onglet — et qu'un contrôle qui remplace
    /// tout le contenu en tient lieu. Sur la carte elle est en bas à droite : là,
    /// le fond EST ce qu'on regarde, et rien ne doit s'asseoir au milieu. Ici il
    /// n'y a rien à masquer.
    private var gameRow: some View {
        GameSwitch(game: $model.activeGame)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// La recherche, l'entonnoir, et la colonne qu'il déplie — dans UN SEUL
    /// `GlassEffectContainer`.
    ///
    /// Un seul, et c'est tout l'intérêt : le verre ne se fond qu'entre éléments
    /// d'un même conteneur. Les puces naissent donc du bouton et s'y résorbent,
    /// au lieu d'apparaître à côté de lui. La carte en emploie deux — un pour sa
    /// rangée haute, un pour ses puces — et n'obtient pour cette raison qu'un
    /// fondu, jamais la fusion.
    private var searchAndCategories: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("cheats.search.placeholder", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: .capsule)
                    categoryToggleButton
                }
                if showCategories {
                    CheatsFilterBar(
                        categories: model.availableCategories,
                        selectedCategory: model.selectedCategory,
                        onSelect: { model.selectCategory($0) }
                    )
                    // Le point d'ancrage EST le message : la colonne se déploie
                    // depuis le coin où se trouve le bouton, et s'y replie. Une
                    // simple opacité la ferait apparaître de nulle part.
                    .transition(
                        .scale(scale: 0.85, anchor: .topTrailing)
                            .combined(with: .opacity)
                    )
                }
            }
        }
    }

    /// L'entonnoir — même bouton que sur la carte, à une charge près qu'il n'y a
    /// pas : les puces qu'il déploie sont invisibles au repos, donc lui seul peut
    /// dire qu'un filtre est posé. D'où le glyphe plein et le cyan, qui tombent
    /// dans la seule catégorie que `CLAUDE.md` laisse à cette teinte sans
    /// discuter — « l'unique chose qu'un écran veut faire remarquer ».
    private var categoryToggleButton: some View {
        let isFiltering = model.selectedCategory != nil
        return Button {
            // `withAnimation` ICI, et c'est mesuré — contrairement à ce que
            // l'interdiction posée sur `FilterChip` laissait craindre.
            //
            // La distinction est nette : l'action d'une PUCE remplace le contenu
            // de la liste, donc SwiftUI anime l'apparition et la disparition de
            // dizaines de cartes en verre — douze images perdues par tap. Le
            // dépliage du PANNEAU, lui, ne crée ni ne détruit aucune carte : il
            // les décale. Sonde `CADisplayLink`, iPhone 17, trois tours de six
            // allers-retours : une à deux images perdues par tour, pire
            // intervalle 33 à 47 ms, contre zéro perdue et 17 ms au repos.
            //
            // Le premier tour d'une mesure paie un coût de premier passage
            // — 127 à 172 ms — quelle que soit la variante placée en tête. Ne pas
            // le prendre pour le coût de l'animation, c'est l'erreur que la
            // première mesure a failli inscrire ici.
            withAnimation(.snappy) { showCategories.toggle() }
        } label: {
            Image(
                systemName: isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .font(.system(size: 20))
            .foregroundStyle(isFiltering ? NCColor.neonCyan : .white)
            .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("cheats.filter.toggle.a11y"))
        // Ce que dit le cyan, dit à VoiceOver : un filtre est posé.
        .accessibilityAddTraits(isFiltering ? [.isSelected] : [])
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
