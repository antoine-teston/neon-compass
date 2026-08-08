import Testing
@testable import NeonCompass

struct NCColorTests {
    @Test func parsesSixDigitHex() {
        let c = NCColor.RGBA(hex: "#FF3388")
        #expect(c != nil)
        #expect(abs(c!.red - 1.0) < 0.001)
        #expect(abs(c!.green - 0.2) < 0.001)
        #expect(abs(c!.blue - 0.5333) < 0.001)
        #expect(c!.alpha == 1.0)
    }

    @Test func parsesWithoutHashAndLowercase() {
        #expect(NCColor.RGBA(hex: "1fe0e0") != nil)
    }

    /// La rampe doit rendre EXACTEMENT les trois arrêts de la charte à 0, 0,5
    /// et 1 : c'est ce qui garantit qu'un élément teinté par elle est
    /// indiscernable du dégradé posé à côté.
    @Test func rampReturnsTheThreeStopsExactly() {
        for (position, stop) in [(0.0, 0), (0.5, 1), (1.0, 2)] {
            let ramp = NCColor.rampRGBA(position, through: NCColor.sunsetStops)
            #expect(ramp == NCColor.sunsetStops[stop], "position \(position)")
        }
    }

    @Test func rampInterpolatesBetweenStops() {
        let quarter = NCColor.rampRGBA(0.25, through: NCColor.sunsetStops)
        let magenta = NCColor.sunsetStops[0]
        let violet = NCColor.sunsetStops[1]
        // À mi-chemin du premier segment, chaque composante est la moyenne des
        // deux arrêts qui l'encadrent.
        #expect(abs(quarter.red - (magenta.red + violet.red) / 2) < 0.001)
        #expect(abs(quarter.green - (magenta.green + violet.green) / 2) < 0.001)
        #expect(abs(quarter.blue - (magenta.blue + violet.blue) / 2) < 0.001)
    }

    /// Hors bornes, on se rabat sur l'extrémité la plus proche — et surtout on
    /// ne déborde pas du tableau, ce que le `min` de l'index empêche.
    @Test func rampClampsOutOfRange() {
        #expect(NCColor.rampRGBA(-3, through: NCColor.sunsetStops) == NCColor.sunsetStops[0])
        #expect(NCColor.rampRGBA(42, through: NCColor.sunsetStops) == NCColor.sunsetStops[2])
    }

    /// Deux arrêts et non trois : c'est le cas limite du calcul de segment, et
    /// c'est celui du dernier jour du compte à rebours.
    @Test func twoStopRampInterpolatesWithoutOverflowing() {
        #expect(NCColor.rampRGBA(0, through: NCColor.urgentStops) == NCColor.sunsetStops[0])
        #expect(NCColor.rampRGBA(1, through: NCColor.urgentStops) == NCColor.sunsetStops[2])

        let middle = NCColor.rampRGBA(0.5, through: NCColor.urgentStops)
        let magenta = NCColor.sunsetStops[0]
        let orange = NCColor.sunsetStops[2]
        #expect(abs(middle.green - (magenta.green + orange.green) / 2) < 0.001)
    }

    /// Ce qui fait du dernier jour un signal : la rampe d'urgence ne passe par
    /// AUCUN point froid. Le violet est la seule note froide de la charte, et
    /// son bleu est ce qui le trahit.
    @Test func theUrgentRampNeverGoesThroughTheViolet() {
        let violet = NCColor.sunsetStops[1]
        for step in 0...10 {
            let sample = NCColor.rampRGBA(Double(step) / 10, through: NCColor.urgentStops)
            #expect(sample.blue < violet.blue, "position \(Double(step) / 10)")
        }
    }

    @Test func rejectsInvalidHex() {
        #expect(NCColor.RGBA(hex: "#GGGGGG") == nil)
        #expect(NCColor.RGBA(hex: "#FFF") == nil)
        #expect(NCColor.RGBA(hex: "") == nil)
    }
}
