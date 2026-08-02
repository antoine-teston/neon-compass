import SwiftUI

/// La semaine en cours : ce qui rapporte double, ce qui est en promotion, et
/// combien de temps il reste. Le compte à rebours est le produit — un article
/// raconte la semaine, personne ne prévient qu'elle se termine demain.
struct OnlineEventCard: View {
    let event: OnlineEvent
    let now: Date

    private var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.title.resolved(for: languageCode))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            countdown

            if !event.bonuses.isEmpty {
                section("social.event.bonuses") {
                    ForEach(Array(event.bonuses.enumerated()), id: \.offset) { _, bonus in
                        HStack(alignment: .top) {
                            Text(bonus.activity.resolved(for: languageCode))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(bonus.label.resolved(for: languageCode))
                                .foregroundStyle(NCColor.neonCyan)
                        }
                        .font(NCTypography.body)
                    }
                }
            }

            if !event.discounts.isEmpty {
                section("social.event.discounts") {
                    ForEach(Array(event.discounts.enumerated()), id: \.offset) { _, discount in
                        HStack {
                            Text(discount.item.resolved(for: languageCode))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("social.event.percentOff \(discount.percent)")
                                .foregroundStyle(NCColor.neonCyan)
                        }
                        .font(NCTypography.body)
                    }
                }
            }

            if !event.rewards.isEmpty {
                section("social.event.rewards") {
                    ForEach(Array(event.rewards.enumerated()), id: \.offset) { _, reward in
                        // La nature au-dessus du nom, et non en regard : les noms
                        // d'objets font jusqu'à huit mots, un `HStack` les
                        // renverrait à la ligne au milieu.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(reward.kind.localizationKey))
                                .font(.caption)
                                .foregroundStyle(NCColor.neonCyan)
                            Text(reward.item.resolved(for: languageCode))
                                .font(NCTypography.body)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            if let podium = event.podiumVehicle {
                section("social.event.podium") {
                    Text(podium.resolved(for: languageCode))
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Jamais un négatif : passé `endsAt`, `remaining` rend nil et on dit que
    /// c'est terminé.
    @ViewBuilder
    private var countdown: some View {
        if let remaining = event.remaining(at: now) {
            let days = Int(remaining) / 86_400
            let hours = (Int(remaining) % 86_400) / 3600
            Text("social.event.remaining \(days) \(hours)")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
        } else {
            Text("social.event.over")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private func section(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }
}
