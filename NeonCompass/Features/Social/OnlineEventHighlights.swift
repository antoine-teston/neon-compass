import SwiftUI

/// Une ligne « ce qui vaut le coup » : le meilleur bonus, la meilleure remise,
/// la première récompense. Extrait d'`OnlineEventCard` le jour où le héro
/// compact du hub a eu besoin des mêmes lignes — deux copies auraient divergé.
struct OnlineEventHighlight: Identifiable, Equatable {
    let icon: String
    let name: String
    let value: LocalizedStringKey
    var id: String { "\(icon)\(name)" }
}

enum OnlineEventHighlights {
    /// Calculé chez nous, jamais repris d'un « at a glance » de la source.
    static func compute(for event: OnlineEvent, languageCode: String) -> [OnlineEventHighlight] {
        var out: [OnlineEventHighlight] = []
        if let best = event.bonuses.max(by: { rank($0) < rank($1) }) {
            out.append(OnlineEventHighlight(
                icon: OnlineEventFormatting.bonusesIcon,
                name: best.activity.resolved(for: languageCode),
                value: OnlineEventFormatting.label(for: best)
            ))
        }
        if let best = event.discounts.max(by: { $0.percent < $1.percent }) {
            out.append(OnlineEventHighlight(
                icon: OnlineEventFormatting.discountsIcon,
                name: best.item.resolved(for: languageCode),
                value: "social.event.percentOff \(best.percent)"
            ))
        }
        if let first = event.rewards.first {
            out.append(OnlineEventHighlight(
                icon: OnlineEventFormatting.icon(for: first.kind),
                name: first.item.resolved(for: languageCode),
                value: LocalizedStringKey(first.kind.localizationKey)
            ))
        }
        return out
    }

    /// Une prime en pourcentage ne se compare pas à un multiple sur la même
    /// échelle : « +15 % » n'est pas meilleur que « 2× ». Ramenée à un facteur.
    static func rank(_ bonus: OnlineEventBonus) -> Double {
        if let multiplier = bonus.multiplier { return Double(multiplier) }
        if let percent = bonus.percentBonus { return 1 + Double(percent) / 100 }
        return 0
    }

    /// Ce que la carte compacte ne montre pas : toutes les entrées de la
    /// semaine, moins les `shown` déjà affichées. Alimente le « +N › » du héro.
    static func hiddenCount(for event: OnlineEvent, shown: Int) -> Int {
        let total = event.bonuses.count + event.discounts.count
            + event.rewards.count + (event.podiumVehicle != nil ? 1 : 0)
        return max(0, total - shown)
    }
}
