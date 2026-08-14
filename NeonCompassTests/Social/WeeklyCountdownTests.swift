import Testing
@testable import NeonCompass

struct WeeklyCountdownTests {
    @Test func overADayShowsDaysAndHours() {
        let countdown = WeeklyCountdown(remaining: 2 * 86_400 + 14 * 3600 + 30 * 60)
        #expect(countdown.showsDays)
        #expect(countdown.days == 2)
        #expect(countdown.hours == 14)
    }

    /// Le dernier jour, la colonne des jours disparaît — même signal que
    /// `NCCountdownDigits`.
    @Test func lastDayShowsHoursAndMinutes() {
        let countdown = WeeklyCountdown(remaining: 5 * 3600 + 42 * 60)
        #expect(!countdown.showsDays)
        #expect(countdown.hours == 5)
        #expect(countdown.minutes == 42)
    }

    @Test func exactDayBoundaryStillShowsDays() {
        #expect(WeeklyCountdown(remaining: 86_400).showsDays)
        #expect(!WeeklyCountdown(remaining: 86_399).showsDays)
    }

    /// Jamais de chiffres négatifs : l'appelant décide d'afficher « terminé »,
    /// mais s'il affiche des chiffres, ils valent zéro.
    @Test func expiredClampsToZero() {
        let countdown = WeeklyCountdown(remaining: -50)
        #expect(!countdown.showsDays)
        #expect(countdown.hours == 0)
        #expect(countdown.minutes == 0)
    }
}
