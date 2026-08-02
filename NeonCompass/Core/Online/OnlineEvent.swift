import Foundation

struct OnlineEventBonus: Codable, Equatable, Sendable {
    let activity: LocalizedText
    let label: LocalizedText
}

struct OnlineEventDiscount: Codable, Equatable, Sendable {
    let item: LocalizedText
    let percent: Int
}

/// Une fenêtre de bonus et de remises du mode en ligne.
///
/// Distinct de `NewsItem`, et pas par goût de la symétrie : une entrée d'actu
/// vit sur sa date de publication, celle-ci vit sur sa date de FIN. C'est
/// `endsAt` qui gouverne l'affichage et le rappel — jamais un calcul de jour de
/// semaine, la cadence du mode en ligne à venir étant inconnue.
///
/// `status`, `sources`, `processedFrom`, `sourceClaim` et `needsRewrite` sont
/// absents : Codable ignore les clés inconnues, et les URL de sources
/// contiennent les marques. Même règle que `NewsItem`.
struct OnlineEvent: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let game: Game
    let startsAt: Date
    let endsAt: Date
    let title: LocalizedText
    let bonuses: [OnlineEventBonus]
    let discounts: [OnlineEventDiscount]
    let podiumVehicle: LocalizedText?

    private enum CodingKeys: String, CodingKey {
        case id, game, startsAt, endsAt, title, bonuses, discounts, podiumVehicle
    }

    /// Une fonction et non une `static let` : `ISO8601DateFormatter` n'est pas
    /// `Sendable`, et sous concurrence stricte une constante statique non
    /// isolée est refusée à la compilation.
    private static func formatter() -> ISO8601DateFormatter { ISO8601DateFormatter() }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        game = try container.decode(Game.self, forKey: .game)
        title = try container.decode(LocalizedText.self, forKey: .title)
        // Décodage strict des deux dates : un horodatage illisible rendrait
        // l'événement inaffichable de toute façon, et un repli silencieux
        // (« maintenant », « jamais ») produirait un compte à rebours faux —
        // pire qu'une absence. Les deux vérifications sont séparées pour que
        // chacune lève sur SA clé : une erreur qui pointe toujours `.endsAt`
        // enverrait sur la mauvaise piste quand c'est `startsAt` qui est en cause.
        let startsRaw = try container.decode(String.self, forKey: .startsAt)
        let endsRaw = try container.decode(String.self, forKey: .endsAt)
        let formatter = Self.formatter()
        guard let starts = formatter.date(from: startsRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .startsAt,
                in: container,
                debugDescription: "Horodatage ISO 8601 attendu, reçu « \(startsRaw) »"
            )
        }
        guard let ends = formatter.date(from: endsRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .endsAt,
                in: container,
                debugDescription: "Horodatage ISO 8601 attendu, reçu « \(endsRaw) »"
            )
        }
        startsAt = starts
        endsAt = ends
        // Listes optionnelles au schéma : leur absence vaut vide, pas échec.
        bonuses = try container.decodeIfPresent([OnlineEventBonus].self, forKey: .bonuses) ?? []
        discounts = try container.decodeIfPresent([OnlineEventDiscount].self, forKey: .discounts) ?? []
        podiumVehicle = try container.decodeIfPresent(LocalizedText.self, forKey: .podiumVehicle)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let formatter = Self.formatter()
        try container.encode(id, forKey: .id)
        try container.encode(game, forKey: .game)
        try container.encode(formatter.string(from: startsAt), forKey: .startsAt)
        try container.encode(formatter.string(from: endsAt), forKey: .endsAt)
        try container.encode(title, forKey: .title)
        try container.encode(bonuses, forKey: .bonuses)
        try container.encode(discounts, forKey: .discounts)
        try container.encodeIfPresent(podiumVehicle, forKey: .podiumVehicle)
    }

    /// `now` est TOUJOURS passé, jamais lu depuis `Date()` : c'est la seule
    /// façon de tester une fenêtre temporelle.
    func isActive(at now: Date) -> Bool {
        now >= startsAt && now < endsAt
    }

    /// Secondes restantes, ou `nil` si c'est terminé. Jamais une valeur
    /// négative : la vue doit dire « terminé », pas « il reste -3 jours ».
    func remaining(at now: Date) -> TimeInterval? {
        let delta = endsAt.timeIntervalSince(now)
        return delta > 0 ? delta : nil
    }
}
