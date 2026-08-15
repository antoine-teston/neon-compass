import Testing
import CoreGraphics
@testable import NeonCompass

struct HeroPinningTests {
    private let hero = CGRect(x: 0, y: 0, width: 320, height: 100)

    @Test func fullyVisibleHeroIsNotPinned() {
        #expect(!HeroPinning.isPinned(heroFrame: hero, visibleTop: 0))
    }

    /// La maquette : épinglé quand le héro est sorti à ~92 % (il en reste
    /// moins de 8 % sous le bord).
    @Test func almostGoneHeroIsPinned() {
        let frame = hero.offsetBy(dx: 0, dy: -95)   // il reste 5 pt visibles sur 100
        #expect(HeroPinning.isPinned(heroFrame: frame, visibleTop: 0))
    }

    @Test func halfVisibleHeroIsNotPinned() {
        let frame = hero.offsetBy(dx: 0, dy: -50)
        #expect(!HeroPinning.isPinned(heroFrame: frame, visibleTop: 0))
    }

    @Test func zeroHeightNeverPins() {
        #expect(!HeroPinning.isPinned(heroFrame: .zero, visibleTop: 0))
    }
}
