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
            let ramp = NCColor.sunsetRampRGBA(position)
            #expect(ramp == NCColor.sunsetStops[stop], "position \(position)")
        }
    }

    @Test func rampInterpolatesBetweenStops() {
        let quarter = NCColor.sunsetRampRGBA(0.25)
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
        #expect(NCColor.sunsetRampRGBA(-3) == NCColor.sunsetStops[0])
        #expect(NCColor.sunsetRampRGBA(42) == NCColor.sunsetStops[2])
    }

    @Test func rejectsInvalidHex() {
        #expect(NCColor.RGBA(hex: "#GGGGGG") == nil)
        #expect(NCColor.RGBA(hex: "#FFF") == nil)
        #expect(NCColor.RGBA(hex: "") == nil)
    }
}
