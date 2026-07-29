import SwiftUI

struct FeedListView: View {
    @Bindable var model: FeedModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Cartes dépliées, par identifiant.
    ///
    /// Un `Set` d'identifiants et non un drapeau par carte : `LazyVStack` recycle
    /// ses vues au défilement, donc un état porté par la carte serait rendu à une
    /// autre entrée en remontant. L'état appartient à la liste, la carte ne fait
    /// que le lire.
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
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

    /// Une carte se déplie sur place, elle n'ouvre pas d'écran.
    ///
    /// Le corps d'un item fait deux à trois phrases : ouvrir une vue de détail
    /// pour deux lignes de plus ferait payer une navigation, une animation et un
    /// retour arrière pour un gain de trois mots. Le jour où le fil portera de
    /// vrais articles, la question se reposera — pas avant.
    private func card(for item: NewsItem) -> some View {
        let isExpanded = expandedIDs.contains(item.id)

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                if isExpanded { expandedIDs.remove(item.id) } else { expandedIDs.insert(item.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label(categoryTitleKey(item.category), systemImage: categorySymbol(item.category))
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(NCColor.neonCyan)
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
                    .lineLimit(isExpanded ? nil : 3)

                HStack(alignment: .bottom, spacing: 8) {
                    Text(item.body.resolved(for: currentLanguageCode))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        // Replié, trois lignes : assez pour décider si on veut
                        // lire, et c'est ce qui garde plusieurs entrées à
                        // l'écran. Déplié, aucune limite.
                        .lineLimit(isExpanded ? nil : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Le chevron est la seule chose qui dit que la carte
                    // s'ouvre. Sans lui, le texte coupé se lit comme une
                    // troncature subie, pas comme une invitation.
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
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
        .accessibilityHint(isExpanded ? "feed.card.collapse" : "feed.card.expand")
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
