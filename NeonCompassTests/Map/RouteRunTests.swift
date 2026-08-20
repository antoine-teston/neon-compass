import Testing
@testable import NeonCompass

struct RouteRunTests {
    @Test func startsOnTheFirstStep() {
        let run = RouteRun(steps: ["a", "b", "c"])
        #expect(run.currentStepID == "a")
        #expect(run.stepNumber == 1)
        #expect(run.totalSteps == 3)
        #expect(!run.isFinished)
    }

    @Test func emptyRunIsFinishedImmediately() {
        let run = RouteRun(steps: [])
        #expect(run.isFinished)
        #expect(run.currentStepID == nil)
        #expect(run.totalSteps == 0)
    }

    @Test func advanceMovesToTheNextStep() {
        var run = RouteRun(steps: ["a", "b"])
        run.advance(found: [])
        #expect(run.currentStepID == "b")
        #expect(run.stepNumber == 2)
    }

    @Test func advancePastTheLastStepFinishes() {
        var run = RouteRun(steps: ["a"])
        run.advance(found: [])
        #expect(run.isFinished)
        #expect(run.currentStepID == nil)
    }

    @Test func advanceOnAFinishedRunStaysFinished() {
        var run = RouteRun(steps: [])
        run.advance(found: [])
        #expect(run.isFinished)
    }

    @Test func advanceSkipsAnExternallyFoundStep() {
        // « b » a été coché depuis sa fiche pendant le parcours : l'avancement
        // le saute sans état d'erreur (décision 5 de la spec).
        var run = RouteRun(steps: ["a", "b", "c"])
        run.advance(found: ["b"])
        #expect(run.currentStepID == "c")
        #expect(run.stepNumber == 3)
    }

    @Test func advanceSkipsConsecutiveExternallyFoundSteps() {
        var run = RouteRun(steps: ["a", "b", "c", "d"])
        run.advance(found: ["b", "c"])
        #expect(run.currentStepID == "d")
    }

    @Test func advanceFinishesWhenAllRemainingAreFound() {
        var run = RouteRun(steps: ["a", "b"])
        run.advance(found: ["b"])
        #expect(run.isFinished)
    }

    @Test func aSkippedStepIsNeverProposedAgain() {
        // « a » passé sans être trouvé : l'index n'avance que vers l'avant,
        // donc « a » ne revient jamais (décision 3 de la spec).
        var run = RouteRun(steps: ["a", "b", "c"])
        run.advance(found: [])
        #expect(run.currentStepID == "b")
        run.advance(found: [])
        #expect(run.currentStepID == "c")
        run.advance(found: [])
        #expect(run.isFinished)
    }
}
