import SwiftUI

struct FeedListView: View {
    @Bindable var model: FeedModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Une bannière intercalée toutes les cinq entrées, et c'est la SEULE
    /// publicité de cet écran : la bannière ancrée au-dessus de la barre
    /// d'onglets a été retirée.
    ///
    /// Le fil y gagne toute la hauteur de l'écran, et la publicité y gagne
    /// d'être lue — une bannière collée en bas est le premier élément qu'un œil
    /// apprend à ignorer, alors qu'un encart rencontré dans le défilement est
    /// regardé. La contrepartie est assumée : un fil de moins de six entrées ne
    /// porte plus aucune publicité.
    private static let cardsBetweenAds = 5

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

    /// Jamais après la dernière carte : terminer une liste par une publicité,
    /// c'est ce qu'on voit dans les applications qu'on désinstalle.
    private func showsInlineAd(after index: Int) -> Bool {
        guard !proEntitlementModel.isProEntitled else { return false }
        let position = index + 1
        return position % Self.cardsBetweenAds == 0 && position < model.newsItems.count
    }

    /// Même gabarit qu'une carte — mêmes marges, même rayon, même verre.
    ///
    /// Non pour la déguiser en actu, mais parce qu'un encart d'une autre taille
    /// dans une colonne de cartes casse le rythme de lecture : l'œil bute sur
    /// la rupture avant même de lire ce qu'elle contient. `BannerAdView` se
    /// dimensionne lui-même en hauteur ; seule la largeur est alignée ici.
    private var inlineAd: some View {
        BannerAdView()
            .frame(maxWidth: .infinity)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func card(for item: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(categoryTitleKey(item.category), systemImage: categorySymbol(item.category))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(NCColor.neonCyan)
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

            Text(item.body.resolved(for: currentLanguageCode))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                // Le corps d'une actu est un résumé, pas un article : trois
                // lignes suffisent à décider si on veut en savoir plus, et
                // c'est ce qui garde plusieurs entrées visibles à l'écran.
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
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

    private func categoryTitleKey(_ category: NewsCategory) -> LocalizedStringKey {
        switch category {
        case .announcement: "feed.category.announcement"
        case .patch: "feed.category.patch"
        case .event: "feed.category.event"
        }
    }

    private func categorySymbol(_ category: NewsCategory) -> String {
        switch category {
        case .announcement: "megaphone"
        case .patch: "wrench.and.screwdriver"
        case .event: "calendar"
        }
    }
}
