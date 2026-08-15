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

    /// Le texte du label, exposé pour être testé à locale fixée : le chemin
    /// testé et le chemin affiché sont le même — c'est ce qui a manqué quand
    /// l'arrondi par défaut fabriquait « 24h » à 23 h 59.
    ///
    /// `fractionalPart: .hide(rounded: .down)` : sans lui, le reste caché
    /// s'arrondit dans la plus petite unité AFFICHÉE, et les trente dernières
    /// secondes avant la bascule du jour rendaient « 24h » — un jour entier,
    /// au moment précis où la colonne des jours disparaît.
    static func label(remaining: TimeInterval, locale: Locale = .current) -> String {
        let countdown = WeeklyCountdown(remaining: remaining)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> =
            countdown.showsDays ? [.days, .hours] : [.hours, .minutes]
        return Duration.seconds(max(0, remaining)).formatted(
            .units(
                allowed: allowed,
                width: .narrow,
                maximumUnitCount: 2,
                fractionalPart: .hide(rounded: .down)
            ).locale(locale)
        )
    }
}

/// Le texte du rebours, localisé par le système (« 2j 14h », « 2d 14h ») —
/// aucune clé de catalogue, donc rien à traduire ni à couvrir.
struct WeeklyCountdownLabel: View {
    let remaining: TimeInterval

    var body: some View {
        Text(WeeklyCountdown.label(remaining: remaining))
            .font(NCTypography.cardTitle.monospacedDigit())
            .foregroundStyle(NCColor.neonCyan)
            .ncNeonGlow(NCColor.neonCyan)
            .lineLimit(1)
    }
}
