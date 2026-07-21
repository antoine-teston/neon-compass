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

    @Test func rejectsInvalidHex() {
        #expect(NCColor.RGBA(hex: "#GGGGGG") == nil)
        #expect(NCColor.RGBA(hex: "#FFF") == nil)
        #expect(NCColor.RGBA(hex: "") == nil)
    }
}
