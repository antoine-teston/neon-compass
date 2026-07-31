import SwiftUI

/// L'entrée du fil, en entier.
///
/// Remplace le dépliage sur place : la carte reste un résumé de trois lignes, et
/// l'ouverture donne le texte complet plus ce que la carte n'a pas la place de
/// dire. C'est aussi ce qui donne un endroit où faire grandir l'entrée — une
/// carte dépliée n'en avait pas.
struct NewsDetailView: View {
    let item: NewsItem
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Text(item.title.resolved(for: currentLanguageCode))
                        .font(NCTypography.displayTitle)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.body.resolved(for: currentLanguageCode))
                        .font(NCTypography.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)

                    if let confidence = item.confidence {
                        confidenceCard(confidence)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(NCColor.nightSky.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("feed.detail.close", systemImage: "xmark") { onDismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(categoryTitleKey(item.category), systemImage: categorySymbol(item.category))
                .font(NCTypography.cardMeta)
                .foregroundStyle(NCColor.neonCyan)

            Text(item.game.shortLabel)
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(item.game == .leonida ? 0.7 : 0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.08), in: .capsule)

            Spacer(minLength: 8)

            if let date = formattedDate(item.publishedAt) {
                Text(date)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    /// Ce que vaut l'information, dit explicitement.
    ///
    /// C'est la réponse à la question que se pose vraiment quelqu'un qui ouvre
    /// une entrée de ce fil : « est-ce sûr ? ». Trois des entrées les plus utiles
    /// sont des démentis de rumeurs virales — leur valeur tient entièrement à ce
    /// qu'on assume de dire d'où on tient l'information, et à quel point.
    ///
    /// Les URL des sources ne sont PAS affichées, et pas par oubli : elles
    /// contiennent les marques (`gtaboom.com/rockstar-confirms-…`), donc les
    /// montrer mettrait à l'écran la surface de marque que la politique stricte
    /// évite jusqu'à l'approbation. Elles viendront avec la bascule.
    private func confidenceCard(_ confidence: NewsConfidence) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: confidenceSymbol(confidence))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(confidenceTint(confidence))

            VStack(alignment: .leading, spacing: 2) {
                Text(confidenceTitleKey(confidence))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(confidenceTint(confidence))
                Text(confidenceDetailKey(confidence))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// Date longue ici, abrégée sur la carte : une entrée ouverte se lit, elle ne
    /// se balaye pas.
    private func formattedDate(_ isoDate: String) -> String? {
        guard let date = Self.isoFormatter.date(from: isoDate) else { return nil }
        return date.formatted(.dateTime.day().month(.wide).year())
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

    private func confidenceTitleKey(_ confidence: NewsConfidence) -> LocalizedStringKey {
        switch confidence {
        case .confirmedOfficial: "feed.confidence.official"
        case .multiSource: "feed.confidence.corroborated"
        case .singleSource: "feed.confidence.single"
        case .rumor: "feed.confidence.rumor"
        }
    }

    private func confidenceDetailKey(_ confidence: NewsConfidence) -> LocalizedStringKey {
        switch confidence {
        case .confirmedOfficial: "feed.confidence.official.detail"
        case .multiSource: "feed.confidence.corroborated.detail"
        case .singleSource: "feed.confidence.single.detail"
        case .rumor: "feed.confidence.rumor.detail"
        }
    }

    private func confidenceSymbol(_ confidence: NewsConfidence) -> String {
        switch confidence {
        case .confirmedOfficial: "checkmark.seal.fill"
        case .multiSource: "checkmark.circle"
        case .singleSource: "info.circle"
        case .rumor: "questionmark.circle"
        }
    }

    /// Le cyan est déjà l'accent du fil : on ne lui ajoute pas un vert et un
    /// rouge, qui feraient trois lueurs sur un écran où CLAUDE.md en autorise
    /// trois au total. Seule la rumeur se détache, en ambre — c'est le seul
    /// niveau qu'il faut vraiment remarquer.
    private func confidenceTint(_ confidence: NewsConfidence) -> Color {
        switch confidence {
        case .rumor: .orange
        case .confirmedOfficial, .multiSource, .singleSource: NCColor.neonCyan
        }
    }
}
