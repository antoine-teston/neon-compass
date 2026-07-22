import Foundation

enum CheatCategory: String, CaseIterable, Codable, Sendable {
    case player, weapons, vehicles, world, misc
}

enum Platform: String, CaseIterable, Codable, Sendable {
    case ps5, xbox
}

enum GamepadButton: String, Codable, Sendable {
    case up, down, left, right
    case cross, circle, square, triangle
    case a, b, x, y
    case l1, l2, r1, r2
}

/// Champs pipeline-only du schéma (`status`, `verifiedBy`) sont absents ici :
/// Codable ignore silencieusement les clés JSON inconnues au décodage
/// (même stratégie que POI, cf. plan 2).
struct Cheat: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: CheatCategory
    let effect: LocalizedText
    let sequence: [Platform: [GamepadButton]]
    let blocksTrophies: Bool

    enum CodingKeys: String, CodingKey {
        case id, category, effect, sequence, blocksTrophies
    }

    init(id: String, category: CheatCategory, effect: LocalizedText,
         sequence: [Platform: [GamepadButton]], blocksTrophies: Bool) {
        self.id = id
        self.category = category
        self.effect = effect
        self.sequence = sequence
        self.blocksTrophies = blocksTrophies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.category = try container.decode(CheatCategory.self, forKey: .category)
        self.effect = try container.decode(LocalizedText.self, forKey: .effect)
        self.blocksTrophies = try container.decode(Bool.self, forKey: .blocksTrophies)

        let sequenceDict = try container.decode([String: [String]].self, forKey: .sequence)
        var sequence: [Platform: [GamepadButton]] = [:]
        for (platformKey, buttonStrings) in sequenceDict {
            guard let platform = Platform(rawValue: platformKey) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .sequence,
                    in: container,
                    debugDescription: "Invalid platform: \(platformKey)"
                )
            }
            let buttons = try buttonStrings.map { buttonString -> GamepadButton in
                guard let button = GamepadButton(rawValue: buttonString) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .sequence,
                        in: container,
                        debugDescription: "Invalid button: \(buttonString)"
                    )
                }
                return button
            }
            sequence[platform] = buttons
        }
        self.sequence = sequence
    }

    /// Miroir manuel de `init(from:)` : `[Platform: [GamepadButton]]` n'est pas
    /// une clé `String`/`Int`, donc l'encodage `Dictionary` synthétisé par
    /// défaut produirait un tableau plat `[clé, valeur, clé, valeur, …]` au
    /// lieu de l'objet `{"ps5": [...], "xbox": [...]}` que `init(from:)`
    /// attend en lecture — cassant le round-trip encode/decode utilisé par
    /// le cache SwiftData de `CheatContentStore`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(category, forKey: .category)
        try container.encode(effect, forKey: .effect)
        try container.encode(blocksTrophies, forKey: .blocksTrophies)

        var sequenceDict: [String: [String]] = [:]
        for (platform, buttons) in sequence {
            sequenceDict[platform.rawValue] = buttons.map(\.rawValue)
        }
        try container.encode(sequenceDict, forKey: .sequence)
    }
}
