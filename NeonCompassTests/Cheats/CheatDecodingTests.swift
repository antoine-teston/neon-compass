import Foundation
import Testing
@testable import NeonCompass

struct CheatDecodingTests {
    private func decode(_ json: String) throws -> Cheat {
        try JSONDecoder().decode(Cheat.self, from: Data(json.utf8))
    }

    private static let fourModes = """
    {"id":"cheat_gtav_spawn_comet","game":"gtav","category":"vehicles",
     "effect":{"en":"Drops a Comet sports car next to you."},
     "codes":{
       "playstation":{"kind":"buttons","buttons":["r1","circle","r2","right"]},
       "xbox":{"kind":"buttons","buttons":["rb","b","rt","right"]},
       "pc":{"kind":"keyword","keyword":"COMET"},
       "phone":{"kind":"phone","number":"1-999-266-38","mnemonic":"1-999-COMET"}},
     "blocksTrophies":false,"status":"draft","verifiedBy":["gta.fandom.com"]}
    """

    @Test func decodesAllFourModes() throws {
        let cheat = try decode(Self.fourModes)
        #expect(cheat.game == .reference)
        #expect(cheat.codes.count == 4)
        #expect(cheat.codes[.playstation] == .buttons([.r1, .circle, .r2, .right]))
        #expect(cheat.codes[.xbox] == .buttons([.rb, .b, .rt, .right]))
        #expect(cheat.codes[.pc] == .keyword("COMET"))
        #expect(cheat.codes[.phone] == .phone(number: "1-999-266-38", mnemonic: "1-999-COMET"))
        // Reprise de CheatTests.decodesCheatIgnoringPipelineOnlyFields : les
        // champs pipeline-only du schéma n'ont pas d'équivalent dans le modèle
        // et doivent être ignorés sans erreur, pas provoquer un échec.
        #expect(cheat.effect.resolved(for: "en") == "Drops a Comet sports car next to you.")
    }

    @Test func decodesAPhoneOnlyCheat() throws {
        let cheat = try decode("""
        {"id":"cheat_gtav_black_cellphone","game":"gtav","category":"misc",
         "effect":{"en":"Switches your in-game phone to its black theme."},
         "codes":{"phone":{"kind":"phone","number":"1-999-367-3767","mnemonic":"1-999-EMPEROR"}},
         "blocksTrophies":false,"status":"draft","verifiedBy":[]}
        """)
        #expect(cheat.codes.count == 1)
        #expect(cheat.codes[.playstation] == nil)
    }

    @Test func phoneMnemonicIsOptional() throws {
        let cheat = try decode("""
        {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
         "codes":{"phone":{"kind":"phone","number":"1-999-111"}},
         "blocksTrophies":false,"status":"draft","verifiedBy":[]}
        """)
        #expect(cheat.codes[.phone] == .phone(number: "1-999-111", mnemonic: nil))
    }

    // Le socle embarqué et le cache SwiftData relisent ce que le modèle a écrit :
    // un encodage qui ne se relit pas vide l'écran au deuxième lancement, pas au
    // premier. C'est exactement le piège que Cheat.encode(to:) documente déjà
    // pour l'ancien dictionnaire de séquences.
    @Test func survivesAnEncodeDecodeRoundTrip() throws {
        let original = try decode(Self.fourModes)
        let reencoded = try JSONEncoder().encode(original)
        let again = try JSONDecoder().decode(Cheat.self, from: reencoded)
        #expect(again == original)
    }

    @Test func rejectsAnUnknownButton() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{"xbox":{"kind":"buttons","buttons":["up","nope"]}},
             "blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    @Test func rejectsAnUnknownInputMode() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{"switch":{"kind":"buttons","buttons":["up"]}},
             "blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    // Une triche sans aucun code s'afficherait sans pouvoir être saisie.
    @Test func rejectsACheatWithNoCodeAtAll() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{},"blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    @Test func rejectsAnEmptyButtonSequence() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{"xbox":{"kind":"buttons","buttons":[]}},
             "blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    @Test func rejectsAMislabelledPayload() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"id":"cheat_gtav_x","game":"gtav","category":"misc","effect":{"en":"x"},
             "codes":{"pc":{"kind":"keyword","number":"1-999-111"}},
             "blocksTrophies":false,"status":"draft","verifiedBy":[]}
            """)
        }
    }

    // Ce qui décide de la présence du bouton copier. Une séquence de boutons n'a
    // rien à copier : proposer « Copier » y serait une promesse vide.
    @Test func onlyTextCodesAreCopyable() {
        #expect(CheatCode.buttons([.circle, .r1]).copyableText == nil)
        #expect(CheatCode.keyword("COMET").copyableText == "COMET")
        #expect(
            CheatCode.phone(number: "1-999-266-38", mnemonic: "1-999-COMET").copyableText
                == "1-999-266-38"
        )
    }

    // C'est le numéro qu'on copie, pas le mnémonique : un téléphone in-game ne
    // compose pas des lettres.
    @Test func copyingAPhoneCodeYieldsTheDigitsNotTheMnemonic() {
        let code = CheatCode.phone(number: "1-999-724-654-5537", mnemonic: "1-999-PAINKILLER")
        #expect(code.copyableText == "1-999-724-654-5537")
    }

    // Le vrai contenu, décodé pour de vrai : le schéma et le modèle Swift ont
    // déjà divergé une fois — lb/lt/rb/rt autorisés côté schéma, absents côté
    // Swift — et cette divergence ne se voyait dans aucun test unitaire, parce
    // que le test écrivait « l1 » là où le contenu écrivait « lb ».
    //
    // Lit content/ depuis le disque : ne vaut que sur simulateur avec le dépôt
    // monté, ce qui est le cas de Scripts/test.sh. CheatLoaderTests double cet
    // invariant sur le socle embarqué, qui vaut aussi sur appareil.
    @Test func decodesEveryShippedCheatFile() throws {
        // #filePath = <racine>/NeonCompassTests/Cheats/CheatDecodingTests.swift
        let dir = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "content/cheats")
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count == 36)
        for file in files {
            #expect(throws: Never.self, "\(file.lastPathComponent) ne décode pas") {
                try JSONDecoder().decode(Cheat.self, from: Data(contentsOf: file))
            }
        }
    }
}
