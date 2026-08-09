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

                    // `featuredTitle` et non `displayTitle` : c'est la taille
                    // qu'a déjà le titre sur la carte à la une, donc l'ouverture
                    // ne le fait plus grossir d'un écran à l'autre. Et sur un
                    // titre de quatre lignes, les six points gagnés valent trois
                    // lignes de corps de plus au-dessus du pli — ce qui est
                    // exactement ce que cet écran cherche.
                    Text(item.title.resolved(for: currentLanguageCode))
                        .font(NCTypography.featuredTitle)
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
            // Même partage que sur la carte du fil : le même élément ne peut pas
            // se présenter autrement d'un écran à l'autre.
            Label {
                Text(item.category.titleKey)
                    .foregroundStyle(.white.opacity(0.55))
            } icon: {
                Image(systemName: item.category.symbolName)
                    .foregroundStyle(NCColor.neonCyan)
            }
            .font(NCTypography.cardMeta)

            Text(item.game.shortLabel)
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(item.game == .leonida ? 0.7 : 0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.08), in: .capsule)
                .breathingHighlight(item.game == .leonida)

            Spacer(minLength: 8)

            if let date = formattedDate {
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
    private var formattedDate: String? {
        item.publishedDate?.formatted(.dateTime.day().month(.wide).year())
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
