import SwiftUI

/// La semaine en cours, en résumé. Le détail vit dans une feuille.
///
/// Pourquoi ce découpage : la version précédente empilait tout — sept bonus, dix
/// remises, cinq récompenses — soit vingt-deux lignes de même poids visuel sur une
/// seule carte. Personne ne lit vingt-deux lignes ; on cherche « qu'est-ce qui vaut
/// le coup cette semaine » et « combien de temps il reste ». La carte répond à ces
/// deux questions, et n'ouvre le reste que sur demande.
struct OnlineEventCard: View {
    let event: OnlineEvent
    let now: Date

    /// La catégorie dont la feuille est ouverte. `nil` = fermée.
    @State private var opened: OnlineEventCategory?

    private var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // La FENÊTRE, pas le titre du contenu. Vu au simulateur : « Mise à
            // jour hebdomadaire — 2026-07-30 » passait à la ligne, et sa date ISO
            // n'apprenait rien au-dessus d'un compte à rebours qui dit déjà le
            // temps restant. Les bornes de la semaine, elles, répondent à la seule
            // question que le titre laissait ouverte : de quelle semaine parle-t-on.
            // Formatées par la locale, donc « 30 juil. – 5 août » et non une date ISO.
            Text(event.startsAt..<event.endsAt, format: .interval.day().month(.abbreviated))
                .font(NCTypography.cardTitle)
                .foregroundStyle(.white)

            OnlineEventCountdown(endsAt: event.endsAt)

            if !highlights.isEmpty {
                separator
                highlightsBlock
            }

            if OnlineEventCategory.allCases.contains(where: { $0.count(in: event) > 0 }) {
                separator
                categories
            }

            if let podium = event.podiumVehicle {
                separator
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("social.event.podium", icon: OnlineEventFormatting.podiumIcon)
                    Text(podium.resolved(for: languageCode))
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .sheet(item: $opened) { category in
            OnlineEventDetailSheet(event: event, category: category)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
    }

    // MARK: - Ce qui vaut le coup

    /// Calculé chez nous, jamais repris d'un « at a glance » de la source : le
    /// meilleur multiplicateur, la meilleure remise, la première chose à réclamer.
    private var highlights: [Highlight] {
        var out: [Highlight] = []
        if let best = event.bonuses.max(by: { rank($0) < rank($1) }) {
            out.append(
                Highlight(
                    icon: OnlineEventFormatting.bonusesIcon,
                    name: best.activity.resolved(for: languageCode),
                    value: OnlineEventFormatting.label(for: best)
                )
            )
        }
        if let best = event.discounts.max(by: { $0.percent < $1.percent }) {
            out.append(
                Highlight(
                    icon: OnlineEventFormatting.discountsIcon,
                    name: best.item.resolved(for: languageCode),
                    value: "social.event.percentOff \(best.percent)"
                )
            )
        }
        if let first = event.rewards.first {
            out.append(
                Highlight(
                    icon: OnlineEventFormatting.icon(for: first.kind),
                    name: first.item.resolved(for: languageCode),
                    value: LocalizedStringKey(first.kind.localizationKey)
                )
            )
        }
        return out
    }

    /// Une prime en pourcentage ne se compare pas à un multiple sur la même
    /// échelle : « +15 % » n'est pas meilleur que « 2× ». Ramenée à un facteur.
    private func rank(_ bonus: OnlineEventBonus) -> Double {
        if let multiplier = bonus.multiplier { return Double(multiplier) }
        if let percent = bonus.percentBonus { return 1 + Double(percent) / 100 }
        return 0
    }

    private var highlightsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("social.event.highlights", icon: OnlineEventFormatting.highlightsIcon)
            ForEach(highlights) { highlight in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: highlight.icon)
                        .font(.caption)
                        .foregroundStyle(NCColor.neonCyan)
                        .frame(width: 16)
                    Text(highlight.name)
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text(highlight.value)
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(NCColor.neonCyan)
                }
            }
        }
    }

    // MARK: - Les portes vers le détail

    private var categories: some View {
        VStack(spacing: 0) {
            ForEach(OnlineEventCategory.allCases) { category in
                let count = category.count(in: event)
                if count > 0 {
                    Button { opened = category } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .foregroundStyle(NCColor.neonCyan)
                                .frame(width: 20)
                            Text(category.titleKey)
                                .font(NCTypography.body)
                                .foregroundStyle(.white)
                            Spacer()
                            // `format:` et non un littéral qui interpolerait le
                            // compte : ce dernier serait pris pour une clé de
                            // catalogue « %lld », introuvable, et l'app
                            // afficherait le nom de la clé. Un test de
                            // couverture l'a refusé — à raison. (Il lit le texte
                            // brut, commentaires compris : ne pas écrire le motif
                            // fautif ici, même pour l'illustrer.)
                            Text(count, format: .number)
                                .font(NCTypography.cardMeta.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    // Toute la ligne est la cible, pas seulement le texte : une
                    // cible haute de 20 pt sur un libellé court est ratée une fois
                    // sur trois au pouce.
                    .contentShape(.rect)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ key: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(key)
                .font(NCTypography.cardMeta)
        }
        .foregroundStyle(.white.opacity(0.5))
    }

    private struct Highlight: Identifiable {
        let icon: String
        let name: String
        let value: LocalizedStringKey
        var id: String { "\(icon)\(name)" }
    }
}

/// Les trois listes qu'une semaine porte. `Identifiable` pour servir directement de
/// valeur à `.sheet(item:)` — sans quoi il faudrait un booléen ET une sélection,
/// donc deux états à garder d'accord.
enum OnlineEventCategory: String, CaseIterable, Identifiable {
    case bonuses
    case discounts
    case rewards

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .bonuses: "social.event.bonuses"
        case .discounts: "social.event.discounts"
        case .rewards: "social.event.rewards"
        }
    }

    var icon: String {
        switch self {
        case .bonuses: OnlineEventFormatting.bonusesIcon
        case .discounts: OnlineEventFormatting.discountsIcon
        case .rewards: OnlineEventFormatting.rewardsIcon
        }
    }

    func count(in event: OnlineEvent) -> Int {
        switch self {
        case .bonuses: event.bonuses.count
        case .discounts: event.discounts.count
        case .rewards: event.rewards.count
        }
    }
}
