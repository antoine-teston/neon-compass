import Foundation
import Testing
@testable import NeonCompass

struct InterstitialSessionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func aFreshSessionHasShownNothing() {
        #expect(InterstitialSession().shownCount == 0)
    }

    @Test func recordingAShowIncrementsTheCount() {
        var session = InterstitialSession()
        session.recordShown()
        #expect(session.shownCount == 1)
    }

    /// Le cas iPad : la tablette posée à côté de la télé toute la soirée. Le
    /// processus ne meurt jamais, donc sans ce réarmement « un par session »
    /// deviendrait « un par jour ».
    @Test func fiveMinutesInBackgroundRearmsTheCounter() {
        var session = InterstitialSession()
        session.recordShown()
        session.didEnterBackground(at: start)
        session.willEnterForeground(at: start.addingTimeInterval(300))
        #expect(session.shownCount == 0)
    }

    @Test func fourMinutesFiftyNineSecondsDoesNotRearm() {
        var session = InterstitialSession()
        session.recordShown()
        session.didEnterBackground(at: start)
        session.willEnterForeground(at: start.addingTimeInterval(299))
        #expect(session.shownCount == 1)
    }

    /// Un retour au premier plan sans passage par l'arrière-plan ne doit rien
    /// réarmer : sinon n'importe quel événement de cycle de vie parasite
    /// offrirait un interstitiel de plus.
    @Test func returningToForegroundWithoutHavingBackgroundedDoesNothing() {
        var session = InterstitialSession()
        session.recordShown()
        session.willEnterForeground(at: start.addingTimeInterval(10_000))
        #expect(session.shownCount == 1)
    }

    /// Le séjour est CONSOMMÉ par le premier retour. Sans cela, un second
    /// `willEnterForeground` rejouerait le même vieux séjour et réarmerait une
    /// session qui vient à peine de commencer.
    @Test func aBackgroundStayIsConsumedByTheFirstReturn() {
        var session = InterstitialSession()
        session.didEnterBackground(at: start)
        session.willEnterForeground(at: start.addingTimeInterval(300))
        session.recordShown()
        session.willEnterForeground(at: start.addingTimeInterval(600))
        #expect(session.shownCount == 1)
    }
}
