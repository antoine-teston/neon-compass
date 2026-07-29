import Foundation

/// Comment un code se saisit.
///
/// Ce n'est pas une plate-forme : les combos sont identiques de la PS3 à la PS5
/// et de la Xbox 360 aux Series, d'où `playstation` et non `ps5`.
enum CheatInputMode: String, CaseIterable, Codable, Sendable {
    case playstation, xbox, pc, phone

    /// Le mode par défaut au premier lancement. Le téléphone est le seul où les
    /// 36 codes existent tous — la manette n'en couvre que 31 : un nouvel
    /// utilisateur ne tombe donc jamais sur une liste amputée sans comprendre
    /// pourquoi.
    static let `default`: CheatInputMode = .phone
}

/// Un code, dans la forme qu'impose son mode de saisie.
///
/// Union étiquetée plutôt que trois champs optionnels : les trois formes ne se
/// rendent pas de la même façon — une séquence de glyphes, un mot-clé à taper,
/// un numéro à composer — et deux d'entre elles se copient tandis que la
/// troisième n'a rien à copier. Un type qui rend ces cas exclusifs empêche la
/// vue d'avoir à traiter un état impossible.
enum CheatCode: Equatable, Sendable {
    case buttons([GamepadButton])
    case keyword(String)
    case phone(number: String, mnemonic: String?)
}

extension CheatCode: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, buttons, keyword, number, mnemonic
    }

    private enum Kind: String, Codable {
        case buttons, keyword, phone
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .buttons:
            let raw = try container.decode([String].self, forKey: .buttons)
            let buttons = try raw.map { token -> GamepadButton in
                guard let button = GamepadButton(rawValue: token) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .buttons, in: container,
                        debugDescription: "Bouton inconnu : \(token)"
                    )
                }
                return button
            }
            guard !buttons.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .buttons, in: container,
                    debugDescription: "Séquence de boutons vide"
                )
            }
            self = .buttons(buttons)
        case .keyword:
            self = .keyword(try container.decode(String.self, forKey: .keyword))
        case .phone:
            self = .phone(
                number: try container.decode(String.self, forKey: .number),
                mnemonic: try container.decodeIfPresent(String.self, forKey: .mnemonic)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .buttons(let buttons):
            try container.encode(Kind.buttons, forKey: .kind)
            try container.encode(buttons.map(\.rawValue), forKey: .buttons)
        case .keyword(let keyword):
            try container.encode(Kind.keyword, forKey: .kind)
            try container.encode(keyword, forKey: .keyword)
        case .phone(let number, let mnemonic):
            try container.encode(Kind.phone, forKey: .kind)
            try container.encode(number, forKey: .number)
            try container.encodeIfPresent(mnemonic, forKey: .mnemonic)
        }
    }
}

extension CheatCode {
    /// Ce qu'il y a à mettre dans le presse-papiers, ou `nil` quand il n'y a
    /// rien à copier : on ne copie pas une séquence de boutons.
    var copyableText: String? {
        switch self {
        case .buttons: nil
        case .keyword(let keyword): keyword
        case .phone(let number, _): number
        }
    }
}
