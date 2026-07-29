import Testing
@testable import NeonCompass

struct CheatLoaderTests {
    // Sans socle, l'écran Codes est vide au premier lancement et hors ligne —
    // le contenu n'arrivant que du CDN ou de Firestore. C'est ce que ce test
    // garde : un `Resources/Cheats` mal déclaré dans project.yml rend
    // `bundled` vide sans casser le build.
    @Test func bundledSeedCarriesEveryCheat() {
        #expect(CheatLoader.bundled.count == 36)
    }

    @Test func bundledSeedIsAllGTAV() {
        #expect(CheatLoader.bundled.allSatisfy { $0.game == .reference })
    }

    @Test func everyBundledCheatHasAtLeastOneCode() {
        #expect(CheatLoader.bundled.allSatisfy { !$0.codes.isEmpty })
    }

    // Ces quatre chiffres sont le résultat mesuré du recoupement sur une seconde
    // source : la source primaire seule donnait 36 / 34 / 29 / 28.
    @Test func thePhoneIsTheOnlyModeThatCoversEverything() {
        let byMode = Dictionary(
            uniqueKeysWithValues: CheatInputMode.allCases.map { mode in
                (mode, CheatLoader.bundled.filter { $0.codes[mode] != nil }.count)
            }
        )
        #expect(byMode[.phone] == 36)
        #expect(byMode[.pc] == 35)
        #expect(byMode[.xbox] == 31)
        #expect(byMode[.playstation] == 31)
    }

    // Cinq codes n'ont aucun combo manette : c'est le cas que le groupe replié
    // de la liste existe pour traiter, et le compte sert de vigie si le contenu
    // change sans que l'UI soit revue.
    @Test func fiveCheatsAreUnreachableWithAController() {
        let padless = CheatLoader.bundled.filter {
            $0.codes[.playstation] == nil && $0.codes[.xbox] == nil
        }
        #expect(padless.count == 5)
    }
}
