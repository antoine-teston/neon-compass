import SwiftUI

struct CheatsListView: View {
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(FavoritesLiveActivityController.self) private var liveActivity
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Le panneau de rubriques est-il déployé ?
    ///
    /// État de VUE, pas de modèle : rien ne l'écrit dans `UserDefaults`, donc il
    /// ne survit pas à un relancement. Il survit en revanche à un changement
    /// d'onglet, `RootView` gardant ses écrans vivants dans un `ZStack`.
    @State private var showCategories = false

    /// Le bas de la ligne de recherche, dans le repère de l'écran.
    ///
    /// C'est ce qui permet au panneau de SUIVRE cette ligne alors qu'il n'est plus
    /// dans le flux. Sans cette mesure, il faudrait épingler l'en-tête pour lui
    /// donner un point d'ancrage fixe — et payer sa hauteur en permanence.
    @State private var searchRowBottom: CGFloat = 0

    /// Ouverte quand le plafond a refusé un favori. Le refus lui-même vit dans
    /// le modèle ; la vue ne fait qu'en montrer la conséquence.
    /// Pourquoi le paywall s'ouvre. Deux refus le déclenchent — le plafond des
    /// favoris et l'épinglage — et ils ne disent pas la même chose.
    ///
    /// Une énumération et non une `LocalizedStringKey` optionnelle : `sheet(item:)`
    /// veut un `Identifiable`, et une clé de chaîne ne l'est pas. Elle porte donc
    /// son propre libellé.
    enum PaywallReason: String, Identifiable {
        case favoritesCap, pinning
        var id: String { rawValue }

        var message: LocalizedStringKey {
            switch self {
            case .favoritesCap: "cheats.favorites.capReached"
            case .pinning: "cheats.favorites.pinIsPro"
            }
        }
    }

    @State private var paywallReason: PaywallReason?

    private static let screenSpace = "cheatsScreen"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Le fond est HORS du flou, sans quoi le flou irait chercher du vide
            // au ras des bords de l'écran et y laisserait un liseré.
            NCColor.nightSky.ignoresSafeArea()

            list
                // Le flou porte sur l'écran ENTIER, entonnoir compris : c'est un
                // menu qui s'ouvre par-dessus, pas un tiroir qui pousse. Léger —
                // il doit reculer le contenu d'un plan, pas le rendre illisible.
                .blur(radius: showCategories ? 3 : 0)
                // Sans quoi on pourrait taper une carte à travers le flou.
                .allowsHitTesting(!showCategories)

            if showCategories {
                dismissLayer
                categoryPanel
            }
        }
        .coordinateSpace(.named(Self.screenSpace))
        .sheet(item: $paywallReason) { PaywallView(reason: $0.message) }
        // La Live Activity suit ce que la carte montre : poser une étoile,
        // changer de mode de saisie ou de jeu doit se voir sur l'écran
        // verrouillé, sans quoi elle afficherait un code qu'on ne joue plus.
        .task(id: model.liveActivityState) {
            guard liveActivity.isRunning else { return }
            await liveActivity.update(model.liveActivityState)
        }
    }

    /// Une carte, et le seul endroit de cette liste où l'on étoile.
    ///
    /// Le plafond refuse en rendant `false` ; la vue ouvre alors Pro plutôt que
    /// de laisser le tap sans effet. Une étoile qui ne s'allume pas et n'explique
    /// rien serait lue comme une panne.
    private func card(_ cheat: Cheat, code: CheatCode) -> some View {
        CheatCard(
            cheat: cheat,
            code: code,
            isFavorite: model.isFavorite(cheat),
            onTap: { onSelect(cheat) },
            onToggleFavorite: {
                let accepted = model.toggleFavorite(
                    cheat, isProEntitled: proEntitlementModel.isProEntitled
                )
                if !accepted { paywallReason = .favoritesCap }
            }
        )
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                // L'ordre de l'entonnoir, dont le premier cran est monté d'un
                // étage : le jeu se choisit dans la barre haute, puis le mode de
                // saisie, puis la recherche. La bascule tenait ici une ligne
                // entière pour deux chiffres romains.
                inputModePicker
                searchRow

                let flatIndex = model.flatIndexByID
                if !model.favoriteSection.isEmpty {
                    FavoritesCard(
                        cheats: model.favoriteSection,
                        inputMode: model.activeInputMode,
                        favoriteCount: model.favoriteCount,
                        showsCount: !proEntitlementModel.isProEntitled,
                        isAtCap: model.isAtFavoriteCap(
                            isProEntitled: proEntitlementModel.isProEntitled
                        ),
                        showsAll: model.filter == .favorites,
                        // Caché quand le système refuse les activités : un bouton
                        // qui ne peut rien faire est pire qu'absent.
                        isPinned: liveActivity.isAvailable ? liveActivity.isRunning : nil,
                        onSelect: onSelect,
                        onRemove: { cheat in
                            // Un retrait n'est jamais refusé : le plafond ne
                            // porte que sur l'ajout. Le résultat est donc ignoré
                            // ici en connaissance de cause.
                            model.toggleFavorite(
                                cheat, isProEntitled: proEntitlementModel.isProEntitled
                            )
                        },
                        onShowAll: { select(.favorites) },
                        onTogglePin: togglePin
                    )
                }
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
                            card(cheat, code: code)
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
    }

    /// La recherche et l'entonnoir. Elle se mesure : c'est elle que le panneau
    /// suit, depuis l'extérieur du flux.
    private var searchRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                TextField("cheats.search.placeholder", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .glassEffect(.regular, in: .capsule)
                categoryToggleButton
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .named(Self.screenSpace)).maxY
        } action: {
            searchRowBottom = $0
        }
    }

    /// Le panneau, POSÉ SUR l'écran et non inséré dedans.
    ///
    /// Il vit dans le `ZStack` et non dans la liste : inséré dans le flux, il
    /// poussait toutes les cartes vers le bas. Il se cale sous la ligne de
    /// recherche par la mesure de celle-ci, ce qui lui permet de la suivre quand
    /// on a déjà défilé — un panneau ancré au haut de l'écran flotterait au milieu
    /// de nulle part dans ce cas.
    private var categoryPanel: some View {
        CheatsFilterBar(
            categories: model.availableCategories,
            filter: model.filter,
            // Ce que le jeu ET le mode actifs sauraient afficher, pas le compte
            // du plafond : celui-ci porte aussi sur l'autre jeu, et la puce
            // n'aurait alors qu'une liste vide à rendre.
            hasFavorites: model.hasDisplayableFavorites,
            onSelect: { select($0) }
        )
        .padding(.horizontal, 16)
        .offset(y: searchRowBottom + 10)
        // Le point d'ancrage EST le message : la colonne se déploie depuis le coin
        // où se trouve le bouton, et s'y replie. Une simple opacité la ferait
        // apparaître de nulle part.
        .transition(
            .scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity)
        )
    }

    /// Taper à côté referme. Transparent et non un voile sombre : le flou dit déjà
    /// que le contenu est en retrait, et l'assombrir en plus écraserait le verre
    /// des puces, qui n'a plus rien à réfracter sur du noir.
    private var dismissLayer: some View {
        Color.clear
            .contentShape(.rect)
            .ignoresSafeArea()
            .onTapGesture { close() }
            .accessibilityHidden(true)
    }

    /// Choisir referme — c'est un menu, et un menu se ferme sur son choix.
    ///
    /// Les deux mutations ne portent PAS la même animation, et c'est tout le sujet.
    /// Le repli du panneau s'anime ; le refiltrage de la liste, non. Sans la
    /// transaction muette, l'animation du repli emporterait le remplacement de la
    /// liste dans le même passage — ce sont les douze images perdues par tap
    /// mesurées sur `FeedFilterBar`.
    private func select(_ filter: CheatFilter) {
        var silent = Transaction()
        silent.disablesAnimations = true
        withTransaction(silent) { model.select(filter) }
        close()
    }

    /// Épingler est réservé à Pro — c'est la fonctionnalité vendue, pas les
    /// favoris eux-mêmes, que tout le monde garde.
    private func togglePin() {
        guard proEntitlementModel.isProEntitled else {
            paywallReason = .pinning
            return
        }
        if liveActivity.isRunning {
            Task { await liveActivity.stop() }
        } else {
            liveActivity.start(
                game: model.activeGame.shortLabel, state: model.liveActivityState
            )
        }
    }

    private func close() {
        withAnimation(.snappy) { showCategories = false }
    }

    /// L'entonnoir — même bouton que sur la carte, à une charge près qu'il n'y a
    /// pas : les puces qu'il déploie sont invisibles au repos, donc lui seul peut
    /// dire qu'un filtre est posé. D'où le glyphe plein et le cyan, qui tombent
    /// dans la seule catégorie que `CLAUDE.md` laisse à cette teinte sans
    /// discuter — « l'unique chose qu'un écran veut faire remarquer ».
    private var categoryToggleButton: some View {
        // `model.filter != .none` et NON `selectedCategory != nil` : celui-ci ne
        // déballe que le cas `.category`, donc l'entonnoir restait éteint sous
        // « Favoris » — alors qu'il est le seul élément à pouvoir dire qu'une
        // restriction est posée, les puces étant invisibles au repos.
        let isFiltering = model.filter != .none
        return Button {
            // `withAnimation` ICI, et c'est mesuré — contrairement à ce que
            // l'interdiction posée sur `FilterChip` laissait craindre.
            //
            // La distinction est nette : l'action d'une PUCE remplace le contenu
            // de la liste, donc SwiftUI anime l'apparition et la disparition de
            // dizaines de cartes en verre — douze images perdues par tap. Le
            // panneau, lui, ne touche à aucune carte : il se pose PAR-DESSUS.
            //
            // Sonde `CADisplayLink`, iPhone 17, flou compris, trois tours de six
            // ouvertures : une à deux images perdues par tour, pire intervalle 33
            // à 34 ms, contre zéro perdue et 17 ms au repos. Animer un flou plein
            // écran par-dessus une pile de verre ne coûte donc rien de mesurable
            // ici — ce qui ne se devinait pas, d'où la mesure.
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
