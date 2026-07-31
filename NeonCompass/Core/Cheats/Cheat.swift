import Foundation

enum CheatCategory: String, CaseIterable, Codable, Sendable {
    case player, weapons, vehicles, world, misc
}

enum GamepadButton: String, CaseIterable, Codable, Sendable {
    case up, down, left, right
    case cross, circle, square, triangle
    case a, b, x, y
    case l1, l2, r1, r2
    // Les gâchettes Xbox. Le schéma les autorisait déjà ; leur absence ici
    // faisait lever `init(from:)` sur toute séquence Xbox, le fichier était
    // rejeté, et l'écran Codes restait vide — attribué à l'absence de contenu.
    // Aucun test ne le voyait, parce que les tests écrivaient « l1 » là où le
    // contenu écrivait « lb ».
    case lb, lt, rb, rt
}

/// Champs pipeline-only du schéma (`status`, `verifiedBy`) absents ici :
/// Codable ignore silencieusement les clés JSON inconnues au décodage
/// (même stratégie que POI, cf. plan 2).
struct Cheat: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let game: Game
    let category: CheatCategory
    let effect: LocalizedText
    let codes: [CheatInputMode: CheatCode]
    let blocksTrophies: Bool

    enum CodingKeys: String, CodingKey {
        case id, game, category, effect, codes, blocksTrophies
    }

    init(
        id: String,
        game: Game,
        category: CheatCategory,
        effect: LocalizedText,
        codes: [CheatInputMode: CheatCode],
        blocksTrophies: Bool
    ) {
        self.id = id
        self.game = game
        self.category = category
        self.effect = effect
        self.codes = codes
        self.blocksTrophies = blocksTrophies
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.game = try container.decode(Game.self, forKey: .game)
        self.category = try container.decode(CheatCategory.self, forKey: .category)
        self.effect = try container.decode(LocalizedText.self, forKey: .effect)
        self.blocksTrophies = try container.decode(Bool.self, forKey: .blocksTrophies)

        let raw = try container.decode([String: CheatCode].self, forKey: .codes)
        var codes: [CheatInputMode: CheatCode] = [:]
        for (key, code) in raw {
            guard let mode = CheatInputMode(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .codes, in: container,
                    debugDescription: "Mode de saisie inconnu : \(key)"
                )
            }
            codes[mode] = code
        }
        guard !codes.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .codes, in: container,
                debugDescription: "Aucun code : la triche serait affichée sans pouvoir être saisie"
            )
        }
        self.codes = codes
    }

    /// Miroir manuel de `init(from:)`. `[CheatInputMode: CheatCode]` n'a pas de
    /// clé `String`/`Int`, donc l'encodage `Dictionary` synthétisé produirait un
    /// tableau plat `[clé, valeur, clé, valeur, …]` au lieu de l'objet
    /// `{"phone": {…}}` que la lecture attend — cassant le round-trip dont
    /// dépendent le cache SwiftData de `ContentStore<Cheat>` et le socle
    /// embarqué.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(game, forKey: .game)
        try container.encode(category, forKey: .category)
        try container.encode(effect, forKey: .effect)
        try container.encode(blocksTrophies, forKey: .blocksTrophies)

        var raw: [String: CheatCode] = [:]
        for (mode, code) in codes { raw[mode.rawValue] = code }
        try container.encode(raw, forKey: .codes)
    }
}
