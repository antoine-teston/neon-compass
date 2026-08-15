import SwiftUI

/// La semaine d'un jeu, en deux lignes : fenêtre + rebours, puis les deux
/// meilleures entrées. Toute la carte est une porte vers la fiche complète.
struct WeeklyHeroCard: View {
    let event: OnlineEvent
    let now: Date
    /// Posé par l'écran en largeur régulière pour ouvrir le panneau latéral ;
    /// nil en compact, où la carte présente sa propre feuille.
    var onOpenDetail: (() -> Void)? = nil

    @State private var showsDetail = false

    private var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        Button {
            if let onOpenDetail { onOpenDetail() } else { showsDetail = true }
        } label: {
            card
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsDetail) {
            WeekDetailSheet(event: event, now: now)
        }
    }

    private var card: some View {
        let highlights = Array(
            OnlineEventHighlights.compute(for: event, languageCode: languageCode).prefix(2)
        )
        let hidden = OnlineEventHighlights.hiddenCount(for: event, shown: highlights.count)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Chiffres romains nus (`shortLabel`), jamais la marque.
                Text(verbatim: event.game.shortLabel)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 7))
                Text(event.startsAt..<event.endsAt, format: .interval.day().month(.abbreviated))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 8)
                countdown
            }
            if !highlights.isEmpty {
                perksLine(highlights, hidden: hidden)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Le seul accent lumineux de l'écran. Expiré : « terminé », jamais un
    /// rebours négatif.
    @ViewBuilder
    private var countdown: some View {
        if let remaining = event.remaining(at: now) {
            WeeklyCountdownLabel(remaining: remaining)
        } else {
            Text("social.event.over")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func perksLine(_ highlights: [OnlineEventHighlight], hidden: Int) -> some View {
        // En XXL la ligne passe à la ligne : rien ne se tronque, ça défile.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                if index > 0 {
                    Text(verbatim: "·")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text(highlight.value)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.85))
                Text(highlight.name)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            if hidden > 0 {
                Spacer(minLength: 4)
                Text("social.hub.moreCount \(hidden)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.55))
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}
