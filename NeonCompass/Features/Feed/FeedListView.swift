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
            LazyVStack(alignment: .leading, spacing: 12) {
                // Avant les articles ET avant le fil vide : quand rien n'est
                // encore publié, c'est la seule chose que l'écran a à dire.
                ReleaseCountdownCard()
                if model.newsItems.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(model.newsItems.enumerated()), id: \.element.id) { index, item in
                        card(for: item)
                        if showsInlineAd(after: index) {
                            inlineAd
                        }
                    }
                }
            }
            .padding(16)
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
        // Même présentation que le détail d'un POI et que le paywall : une
        // feuille à hauteur moyenne, redimensionnable. Le fil n'a pas de raison
        // de se présenter autrement que le reste de l'app.
        // `onDismiss` plutôt que la fermeture du bouton : il attrape aussi le
        // glissement vers le bas, qui est la façon dont la plupart des gens
        // referment une feuille. Le coordinateur décide seul s'il montre
        // quelque chose — cet écran ne connaît ni le plafond ni l'abonnement.
        .sheet(item: $openedItem, onDismiss: {
            Task { await interstitialCoordinator.contentConsumed() }
        }) { item in
            NewsDetailView(item: item) { openedItem = nil }
                .presentationDetents([.medium, .large])
        }
    }

    /// Les positions viennent du modèle, tirées une fois par contenu. La vue ne
    /// décide de rien : elle ne fait qu'ajouter la condition qui ne dépend pas
    /// du contenu, l'abonnement.
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
    }

    /// La carte reste un résumé de trois lignes et ouvre l'entrée.
    ///
    /// Elle a d'abord déplié le texte sur place, ce qui suffisait pour deux
    /// lignes de plus. Mais une carte dépliée n'a nulle part où faire grandir
    /// l'entrée : dès qu'il s'agit d'ajouter le niveau de confiance, la date
    /// complète et le reste, il faut un écran à soi.
    private func card(for item: NewsItem) -> some View {
        Button {
            openedItem = item
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // L'icône garde l'accent, le libellé passe en blanc : le mot
                    // ne fait que redire ce que l'icône montre déjà, et une
                    // colonne de six cartes en faisait six accents cyan (voir
                    // `NCColor.neonCyan`).
                    Label {
                        Text(categoryTitleKey(item.category))
                            .foregroundStyle(.white.opacity(0.55))
                    } icon: {
                        Image(systemName: categorySymbol(item.category))
                            .foregroundStyle(NCColor.neonCyan)
                    }
                    .font(NCTypography.cardMeta)
                    gameBadge(item.game)
                    Spacer(minLength: 8)
                    if let date = formattedDate(item.publishedAt) {
                        Text(date)
                            .font(NCTypography.cardMeta)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                Text(item.title.resolved(for: currentLanguageCode))
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(3)

                HStack(alignment: .bottom, spacing: 8) {
                    Text(item.body.resolved(for: currentLanguageCode))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        // Trois lignes : assez pour décider si on veut lire,
                        // et c'est ce qui garde plusieurs entrées à l'écran.
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Le chevron est la seule chose qui dit que la carte ouvre
                    // quelque chose. Sans lui, le texte coupé se lit comme une
                    // troncature subie, pas comme une invitation. Il pointe à
                    // DROITE et non plus vers le bas : ce n'est plus un
                    // dépliage, c'est une ouverture.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
        // Sans style « plain », le bouton teinte tout son contenu de la couleur
        // d'accentuation — titre, corps et pastille comprises.
        .buttonStyle(.plain)
        .accessibilityHint("feed.card.open")
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

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// `publishedAt` est une date ISO courte (plan 3d, tâche 1), pas un `Date` :
    /// c'est ce qui garde le `JSONDecoder` du `ContentStore` générique libre de
    /// toute stratégie de date. Le formatage local ne concerne que l'affichage,
    /// et une chaîne inattendue n'affiche simplement rien plutôt que de faire
    /// tomber la carte.
    private func formattedDate(_ isoDate: String) -> String? {
        guard let date = Self.isoFormatter.date(from: isoDate) else { return nil }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// « VI » ou « V », et rien d'autre.
    ///
    /// Le fil couvre les deux jeux, donc un lecteur doit savoir en un coup d'œil
    /// duquel on lui parle — sinon un braquage du jeu en ligne actuel se lit
    /// comme une révélation sur celui à venir. Pas de texte localisé ici : un
    /// chiffre romain se lit dans les cinq langues.
    ///
    /// Volontairement neutre pour le jeu à venir et discret pour l'autre : c'est
    /// une aide au repérage, pas un troisième accent lumineux sur l'écran
    /// (CLAUDE.md : au plus trois par écran, et le cyan en prend déjà un).
    private func gameBadge(_ game: NewsGame) -> some View {
        Text(game.shortLabel)
            .font(NCTypography.cardMeta)
            .foregroundStyle(.white.opacity(game == .leonida ? 0.7 : 0.4))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.08), in: .capsule)
    }

    private func categoryTitleKey(_ category: NewsCategory) -> LocalizedStringKey {
        switch category {
        case .announcement: "feed.category.announcement"
        case .patch: "feed.category.patch"
        case .event: "feed.category.event"
        case .guide: "feed.category.guide"
        case .business: "feed.category.business"
        case .community: "feed.category.community"
        }
    }

    private func categorySymbol(_ category: NewsCategory) -> String {
        switch category {
        case .announcement: "megaphone"
        case .patch: "wrench.and.screwdriver"
        case .event: "calendar"
        case .guide: "lightbulb"
        case .business: "tag"
        case .community: "person.2"
        }
    }
}
