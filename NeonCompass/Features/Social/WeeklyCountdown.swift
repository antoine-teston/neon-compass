import SwiftUI

/// La décomposition du rebours compact du héro. Pur, donc testé : la vue ne
/// décide de rien.
///
/// Deux unités seulement — jours+heures, puis heures+minutes le dernier jour.
/// Le rebours à la seconde de `NCCountdownDigits` vit dans la fiche complète ;
/// ici on répond à « combien de temps il reste » d'un coup d'œil.
struct WeeklyCountdown: Equatable {
    let showsDays: Bool
    let days: Int
    let hours: Int
    let minutes: Int

    init(remaining: TimeInterval) {
        let total = max(0, Int(remaining))
        showsDays = total >= 86_400
        days = total / 86_400
        hours = showsDays ? (total % 86_400) / 3600 : total / 3600
        minutes = (total % 3600) / 60
    }
}

/// Le texte du rebours, localisé par le système (« 2j 14h », « 2d 14h ») —
/// aucune clé de catalogue, donc rien à traduire ni à couvrir.
struct WeeklyCountdownLabel: View {
    let remaining: TimeInterval

    var body: some View {
        let countdown = WeeklyCountdown(remaining: remaining)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> =
            countdown.showsDays ? [.days, .hours] : [.hours, .minutes]
        Text(
            Duration.seconds(max(0, remaining))
                .formatted(.units(allowed: allowed, width: .narrow, maximumUnitCount: 2))
        )
        .font(NCTypography.cardTitle.monospacedDigit())
        .foregroundStyle(NCColor.neonCyan)
        .ncNeonGlow(NCColor.neonCyan)
        .lineLimit(1)
    }
}
