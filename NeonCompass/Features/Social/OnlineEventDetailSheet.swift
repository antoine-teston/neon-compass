import SwiftUI

/// La liste complète d'une catégorie de la semaine.
///
/// Une feuille et non un écran empilé : aucun écran d'onglet du projet n'a de
/// `NavigationStack`, donc rien ne peut être poussé depuis ici. Une feuille, en
/// revanche, porte le sien — et donc sa barre, son titre et son bouton de
/// fermeture. C'est la seule façon d'avoir une barre d'outils dans cet onglet.
struct OnlineEventDetailSheet: View {
    let event: OnlineEvent
    let category: OnlineEventCategory

    @Environment(\.dismiss) private var dismiss

    private var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        rows
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
            }
            .navigationTitle(Text(category.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("social.event.detail.close") { dismiss() }
                }
            }
        }
        // Deux paliers plutôt qu'une feuille pleine hauteur : dix remises tiennent
        // à mi-écran, et on garde le compte à rebours en vue derrière.
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var rows: some View {
        switch category {
        case .bonuses:
            ForEach(Array(event.bonuses.enumerated()), id: \.offset) { index, bonus in
                row(
                    icon: OnlineEventFormatting.bonusesIcon,
                    name: bonus.activity.resolved(for: languageCode),
                    value: OnlineEventFormatting.label(for: bonus),
                    footnote: bonus.until.map { until in
                        // La seule chose que la prose de la source apporte : ce
                        // bonus dure plus longtemps que la semaine. Une date est un
                        // fait, on peut la reprendre ; sa phrase, non.
                        Text("social.event.bonus.until \(until.formatted(.dateTime.day().month(.wide)))")
                    },
                    isLast: index == event.bonuses.count - 1
                )
            }
        case .discounts:
            ForEach(Array(event.discounts.enumerated()), id: \.offset) { index, discount in
                row(
                    icon: OnlineEventFormatting.discountsIcon,
                    name: discount.item.resolved(for: languageCode),
                    value: "social.event.percentOff \(discount.percent)",
                    footnote: nil,
                    isLast: index == event.discounts.count - 1
                )
            }
        case .rewards:
            ForEach(Array(event.rewards.enumerated()), id: \.offset) { index, reward in
                row(
                    icon: OnlineEventFormatting.icon(for: reward.kind),
                    name: reward.item.resolved(for: languageCode),
                    value: LocalizedStringKey(reward.kind.localizationKey),
                    footnote: nil,
                    isLast: index == event.rewards.count - 1
                )
            }
        }
    }

    /// Le nom à gauche sur deux lignes s'il faut, la valeur à droite sans jamais se
    /// couper : c'est la valeur qu'on scanne en descendant la liste.
    @ViewBuilder
    private func row(
        icon: String,
        name: String,
        value: LocalizedStringKey,
        footnote: Text?,
        isLast: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(NCColor.neonCyan)
                    .frame(width: 18)
                Text(name)
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(value)
                    .font(NCTypography.cardMeta.monospacedDigit())
                    .foregroundStyle(NCColor.neonCyan)
                    .lineLimit(1)
            }
            if let footnote {
                footnote
                    .font(.caption)
                    .foregroundStyle(NCColor.sunsetOrange)
                    .padding(.leading, 30)
            }
        }
        .padding(.vertical, 12)

        if !isLast {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}
