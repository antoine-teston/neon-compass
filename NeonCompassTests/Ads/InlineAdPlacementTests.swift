import Testing
@testable import NeonCompass

struct InlineAdPlacementTests {
    // La variante déterministe est celle qu'utilise l'écran Codes : sa liste se
    // refiltre en continu, donc les positions sont recalculées à chaque
    // évaluation du corps de la vue. Si elles n'étaient pas stables, les encarts
    // sauteraient sous le doigt pendant le défilement.
    @Test func deterministicPositionsAreStableForTheSameCount() {
        for count in 0...40 {
            let first = InlineAdPlacement.positions(itemCount: count)
            #expect(InlineAdPlacement.positions(itemCount: count) == first)
            #expect(InlineAdPlacement.positions(itemCount: count) == first)
        }
    }

    @Test func deterministicGapsStayWithinTheAllowedRange() {
        for count in 0...60 {
            var previous = -1
            for position in InlineAdPlacement.positions(itemCount: count).sorted() {
                let gap = position - previous
                #expect(
                    InlineAdPlacement.gapRange.contains(gap),
                    "écart \(gap) hors bornes pour \(count) éléments"
                )
                previous = position
            }
        }
    }

    @Test func deterministicPlacementNeverEndsTheListWithAnAd() {
        for count in 0...60 {
            for position in InlineAdPlacement.positions(itemCount: count) {
                #expect(position < count - 1, "encart après la dernière carte (\(count) éléments)")
            }
        }
    }

    // Deux cartes : le premier écart possible étant 2, l'encart tomberait après
    // la dernière. Il ne doit donc pas y en avoir.
    @Test func aListTooShortToSeparateAdsGetsNone() {
        #expect(InlineAdPlacement.positions(itemCount: 0).isEmpty)
        #expect(InlineAdPlacement.positions(itemCount: 1).isEmpty)
        #expect(InlineAdPlacement.positions(itemCount: 2).isEmpty)
    }

    // Une liste de 36 codes doit en porter plusieurs, sinon la règle est juste
    // mais inopérante : le garde-fou vérifie qu'on a bien des encarts et pas une
    // liste qui n'en montre aucun.
    @Test func aFullCheatListCarriesSeveralAds() {
        let positions = InlineAdPlacement.positions(itemCount: 36)
        #expect(positions.count >= 7, "seulement \(positions.count) encart(s) sur 36 codes")
        #expect(positions.count <= 18)
    }

    // Le générateur graine doit produire des suites différentes pour des graines
    // différentes — sinon toutes les tailles de liste donneraient les mêmes
    // positions, et la règle d'écart aléatoire serait un décor.
    @Test func differentSeedsProduceDifferentSequences() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        #expect(a.next() != b.next())
    }

    @Test func theSameSeedReplaysTheSameSequence() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        #expect((0..<8).map { _ in a.next() } == (0..<8).map { _ in b.next() })
    }

    // Une graine de zéro — une liste vide — doit rester exploitable : sans le
    // décalage dans `init`, l'état partirait de 0 et la suite serait dégénérée.
    @Test func aZeroSeedStillProducesUsableValues() {
        var generator = SplitMix64(seed: 0)
        let values = (0..<4).map { _ in generator.next() }
        #expect(Set(values).count == 4)
        #expect(!values.contains(0))
    }
}
