import Foundation

/// Un bonus de la semaine : ce qui rapporte plus, et de combien.
///
/// La valeur est un NOMBRE, pas un libellé — c'est ce qui permet à l'app
/// d'afficher « 2× GTA$ », la désignation officielle de la monnaie. La porter dans
/// le contenu échouerait à `check-publishable` (« GTA » est une marque, et ce
/// champ-là est rédigé par nous, pas nominatif) ; la reformuler en « 2× argent »
/// perdrait la désignation. Même raisonnement que `OnlineEventRewardKind` : le
/// texte d'interface vit dans le String Catalog.
struct OnlineEventBonus: Codable, Equatable, Sendable {
    let activity: LocalizedText
    /// « 2× », « 3× ». Exclusif avec `percentBonus`, le schéma l'impose.
    let multiplier: Int?
    /// Une prime en pourcentage plutôt qu'un multiple.
    let percentBonus: Int?
    /// Le bonus porte aussi sur la réputation.
    let includesRP: Bool
    /// Fin propre à CE bonus, présente seulement si elle dépasse celle de la
    /// fenêtre — certains courent une semaine de plus, et la carte le taisait.
    let until: Date?

    private enum CodingKeys: String, CodingKey { case activity, multiplier, percentBonus, includesRP, until }

    /// Une fonction et non une constante : `ISO8601DateFormatter` n'est pas
    /// `Sendable`. Même contrainte que dans `OnlineEvent`.
    private static func dayFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activity = try container.decode(LocalizedText.self, forKey: .activity)
        multiplier = try container.decodeIfPresent(Int.self, forKey: .multiplier)
        percentBonus = try container.decodeIfPresent(Int.self, forKey: .percentBonus)
        includesRP = try container.decodeIfPresent(Bool.self, forKey: .includesRP) ?? false
        // Une date illisible est ignorée plutôt que fatale : contrairement à la
        // fenêtre de l'événement, celle-ci est une précision. La perdre retire une
        // mention, elle ne fabrique pas un compte à rebours faux.
        if let raw = try container.decodeIfPresent(String.self, forKey: .until) {
            until = Self.dayFormatter().date(from: raw)
        } else {
            until = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activity, forKey: .activity)
        try container.encodeIfPresent(multiplier, forKey: .multiplier)
        try container.encodeIfPresent(percentBonus, forKey: .percentBonus)
        try container.encode(includesRP, forKey: .includesRP)
        try container.encodeIfPresent(until.map { Self.dayFormatter().string(from: $0) }, forKey: .until)
    }
}

struct OnlineEventDiscount: Codable, Equatable, Sendable {
    let item: LocalizedText
    let percent: Int
}

/// Comment une récompense de la semaine s'obtient.
///
/// Une énumération FERMÉE et non un libellé localisé, contrairement à
/// `OnlineEventBonus.label` : ce qui s'affiche ici est un texte d'interface, pas
/// une donnée, donc il vit dans le String Catalog comme tout le reste
/// (CLAUDE.md). Le contenu ne transporte que la nature ; le nom de l'objet, lui,
/// est un fait et reste dans `item`.
enum OnlineEventRewardKind: String, Codable, Sendable, CaseIterable {
    case challenge
    case login
    case vehicle
    case cash

    /// Clé du String Catalog. Rendue en `String` et non en `LocalizedStringKey` :
    /// ce type vit dans `Core/` et n'importe pas SwiftUI.
    var localizationKey: String { "social.event.reward.\(rawValue)" }
}

/// Ce qu'il y a à réclamer cette semaine — une livrée, un vêtement, un véhicule
/// offert. C'est la catégorie la plus périssable de la carte : elle expire avec
/// la fenêtre, et personne ne prévient.
struct OnlineEventReward: Codable, Equatable, Sendable {
    let kind: OnlineEventRewardKind
    let item: LocalizedText
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
    let rewards: [OnlineEventReward]
    let podiumVehicle: LocalizedText?

    private enum CodingKeys: String, CodingKey {
        case id, game, startsAt, endsAt, title, bonuses, discounts, rewards, podiumVehicle
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
        // Décodage STRICT des natures, pas un repli silencieux sur « autre » : le
        // schéma ferme l'énumération et `validate` la contrôle en CI, donc une
        // nature inconnue ici signifie du contenu qui n'est pas passé par la
        // chaîne. L'avaler en écartant l'entrée priverait la carte d'une
        // récompense sans que personne l'apprenne — c'est précisément le mode de
        // panne que ce projet passe son temps à supprimer.
        rewards = try container.decodeIfPresent([OnlineEventReward].self, forKey: .rewards) ?? []
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
        try container.encode(rewards, forKey: .rewards)
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
