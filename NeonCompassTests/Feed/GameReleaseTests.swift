import Testing
import Foundation
@testable import NeonCompass

/// Les bornes du rebours de sortie.
///
/// Toutes se lisent depuis un calendrier FIXE, en UTC : sans lui, ces tests
/// passeraient ou tomberaient selon le fuseau de la machine qui les exécute, et
/// le jour J tombe justement à minuit local.
struct GameReleaseTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static var release: Date { GameRelease.date(in: utc) }

    @Test func releaseIsMidnightOnNovember19_2026() {
        let components = Self.utc.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Self.release
        )
        #expect(components.year == 2026)
        #expect(components.month == 11)
        #expect(components.day == 19)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test func oneSecondBeforeStillCountsDown() {
        let phase = GameRelease.phase(at: Self.release.addingTimeInterval(-1), calendar: Self.utc)
        #expect(phase == .countdown(1))
    }

    /// La seule seconde où un rebours pourrait mentir : à zéro pile, on est
    /// sorti, on n'affiche pas « 0j 0h 0m 0s ».
    @Test func theExactSecondOfReleaseIsAlreadyReleased() {
        #expect(GameRelease.phase(at: Self.release, calendar: Self.utc) == .released)
    }

    @Test func stillReleasedOnTheSixthDayAfter() {
        let sixDaysLater = Self.release.addingTimeInterval(6 * 24 * 60 * 60)
        #expect(GameRelease.phase(at: sixDaysLater, calendar: Self.utc) == .released)
    }

    /// La carte se retire d'elle-même : sans cette borne elle resterait en tête
    /// du fil pour toujours.
    @Test func goneOnceTheWindowCloses() {
        let sevenDaysLater = Self.release.addingTimeInterval(GameRelease.releasedWindow)
        #expect(GameRelease.phase(at: sevenDaysLater, calendar: Self.utc) == .gone)
    }

    @Test func longBeforeReleaseTheRemainingTimeIsExact() {
        let tenDaysBefore = Self.release.addingTimeInterval(-10 * 24 * 60 * 60)
        #expect(
            GameRelease.phase(at: tenDaysBefore, calendar: Self.utc)
                == .countdown(10 * 24 * 60 * 60)
        )
    }
}
