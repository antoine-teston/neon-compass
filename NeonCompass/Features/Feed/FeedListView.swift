import SwiftUI

struct FeedListView: View {
    @Bindable var model: FeedModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(InterstitialCoordinator.self) private var interstitialCoordinator
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// L'entrée ouverte, s'il y en a une.
    ///
    /// L'état appartient à la LISTE et pas à la carte : `LazyVStack` recycle ses
    /// vues au défilement, donc un état porté par la carte serait rendu à une
    /// autre entrée en remontant le fil.
    @State private var openedItem: NewsItem?

    var body: some View {
        ScrollView {
            // Les marges horizontales sont posées par chaque élément et non par
            // le `LazyVStack`, et c'est la barre de filtres qui l'exige : une
            // rangée qui défile doit pouvoir glisser bord à bord, sinon ses
            // puces ont l'air coupées à seize points du vide.
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                // Avant les articles ET avant le fil vide : quand rien n'est
                // encore publié, c'est la seule chose que l'écran a à dire.
                ReleaseCountdownCard()
                    .padding(.horizontal, 16)

                if model.newsItems.isEmpty {
                    emptyState
                } else {
                    Section {
                        feedBody
                    } header: {
                        // Épinglée : sans elle en vue, on ne sait plus qu'un
                        // filtre est posé après deux écrans de défilement, et
                        // le fil paraît simplement court.
                        FeedFilterBar(
                            games: model.availableGames,
                            categories: model.availableCategories,
                            selectedGame: model.filter.game,
                            selectedCategory: model.filter.category,
                            onSelectGame: { model.selectGame($0) },
                            onSelectCategory: { model.selectCategory($0) }
                        )
                        .padding(.vertical, 8)
                        // Fond opaque, sinon les cartes défilent visiblement
                        // derrière les puces. C'est la couleur de l'écran : on
                        // ne la voit que lorsqu'il y a quelque chose dessous.
                        .background(NCColor.nightSky)
                    }
                }
            }
            .padding(.vertical, 16)
            // La barre d'onglets flotte au-dessus du contenu : sans cette
            // réserve, la dernière carte finirait dessous. Elle ne dépend pas
            // de Pro — la barre est là pour tout le monde.
            .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
        }
        // Le geste porte sur le ScrollView, donc il reste disponible même
        // quand le fil est vide : c'est précisément l'écran où l'on a le
        // plus envie de réessayer.
        .refreshable { await model.refresh() }
        .background(NCColor.nightSky.ignoresSafeArea())
        // `onDismiss` plutôt que la fermeture du bouton : il attrape aussi le
        // glissement vers le bas, qui est la façon dont la plupart des gens
        // referment une feuille. Le coordinateur décide seul s'il montre
        // quelque chose — cet écran ne connaît ni le plafond ni l'abonnement.
        .sheet(item: $openedItem, onDismiss: {
            Task { await interstitialCoordinator.contentConsumed() }
        }) { item in
            NewsDetailView(item: item) { openedItem = nil }
                // UN SEUL PALIER, et c'est le correctif qui a motivé cet écran.
                // À `.medium`, la feuille s'ouvrait à mi-hauteur : l'en-tête et
                // le titre tenaient, le corps de l'article commençait sous le
                // pli, et il fallait un glissement pour lire la première phrase
                // de ce qu'on venait justement de demander à lire. Réduire une
                // page de texte n'a aucun usage — le palier moyen ne rendait
                // service qu'aux feuilles qui laissent voir une carte derrière.
                .presentationDetents([.large])
        }
    }

    /// La une, puis le reste groupé par tranche de temps.
    @ViewBuilder
    private var feedBody: some View {
        if let featured = model.featuredItem {
            NewsCard(
                item: featured,
                prominence: .featured,
                isNew: model.newItemIDs.contains(featured.id)
            ) { openedItem = featured }
                .padding(.horizontal, 16)
        }

        ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIndex, section in
            sectionHeader(section.period)

            ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                let position = listPosition(section: sectionIndex, item: itemIndex)

                NewsCard(
                    item: item,
                    prominence: .standard,
                    isNew: model.newItemIDs.contains(item.id)
                ) { openedItem = item }
                    .padding(.horizontal, 16)

                if showsInlineAd(after: position) {
                    inlineAd
                }
            }
        }
    }

    /// Le rang d'une carte dans le fil aplati, hors celle à la une.
    ///
    /// Les encarts sont positionnés par le modèle sur une liste plate ; les
    /// tranches de temps ne sont qu'un habillage, et le tirage ne doit pas se
    /// remettre à zéro à chaque en-tête — sans quoi un fil de trois tranches
    /// porterait trois fois plus de publicité qu'un fil d'une seule.
    private func listPosition(section: Int, item: Int) -> Int {
        model.sections.prefix(section).reduce(item) { $0 + $1.items.count }
    }

    private func sectionHeader(_ period: FeedPeriod) -> some View {
        Text(period.titleKey)
            .font(NCTypography.cardMeta)
            // Blanc atténué et non un troisième accent coloré : une tranche de
            // temps est un repère, pas une chose à remarquer. Le cyan des
            // rubriques et le magenta du point de nouveauté prennent déjà les
            // deux accents que cet écran s'autorise.
            .foregroundStyle(.white.opacity(0.5))
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    /// Les positions viennent du modèle, tirées une fois par contenu affiché. La
    /// vue ne décide de rien : elle ne fait qu'ajouter la condition qui ne
    /// dépend pas du contenu, l'abonnement.
    private func showsInlineAd(after index: Int) -> Bool {
        guard !proEntitlementModel.isProEntitled else { return false }
        return model.adPositions.contains(index)
    }

    /// Même gabarit qu'une carte — mêmes marges, même rayon, même verre, et une
    /// annonce dimensionnée pour remplir ce gabarit plutôt qu'une bande fine
    /// perdue dedans.
    ///
    /// Non pour la déguiser en actu, mais parce qu'un encart d'une autre taille
    /// dans une colonne de cartes casse le rythme de lecture : l'œil bute sur
    /// la rupture avant même de lire ce qu'elle contient.
    private var inlineAd: some View {
        BannerAdView(maxHeight: BannerAdView.cardSlotHeight)
            .frame(maxWidth: .infinity)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.system(size: 32))
                .foregroundStyle(NCColor.neonCyan)
            Text("feed.empty")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}
