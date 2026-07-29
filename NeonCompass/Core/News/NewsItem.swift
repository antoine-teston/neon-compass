import Foundation

/// Rubrique d'une entrée du fil.
///
/// Décodage TOLÉRANT : une valeur inconnue retombe sur `.announcement` au lieu
/// de lever. C'est ce qui protège le fil d'une panne totale le jour où le
/// pipeline publie une rubrique qu'une version déjà installée ne connaît pas —
/// sans ça, une seule entrée d'un type neuf ferait échouer le décodage du
/// fragment ENTIER, et les clients d'avant verraient un fil vide sans qu'aucune
/// erreur ne le dise. Ajouter une rubrique cesse donc d'être une opération qui
/// exige que tout le parc soit à jour.
enum NewsCategory: String, CaseIterable, Codable, Sendable {
    /// Information officielle sur le jeu ou son édition.
    case announcement
    /// Mise à jour du jeu, après sa sortie.
    case patch
    /// Rendez-vous daté : diffusion, publication de résultats.
    case event
    /// Service pratique : préchargement, stockage, comment s'y prendre.
    case guide
    /// Prix, précommandes, classements, offres commerciales.
    case business
    /// Ce que fait la communauté : créations, mods, exploits de joueurs.
    case community

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NewsCategory(rawValue: raw) ?? .announcement
    }
}

/// Jeu concerné par une entrée.
///
/// Le fil couvre les deux : la presse spécialisée parle autant du jeu en ligne
/// actuel que de celui à venir, et un compagnon qui masquerait tout le premier
/// se priverait des deux tiers de l'actualité. Mais un lecteur doit savoir en un
/// coup d'œil de quoi on lui parle — d'où la pastille sur la carte.
///
/// Réutilise le vocabulaire de `MapGame` (`leonida` / `gtav`) plutôt que d'en
/// inventer un second : deux vocabulaires pour la même distinction finissent
/// toujours par diverger.
enum NewsGame: String, CaseIterable, Codable, Sendable {
    case leonida
    case reference = "gtav"

    var shortLabel: String {
        switch self {
        case .leonida: "VI"
        case .reference: "V"
        }
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NewsGame(rawValue: raw) ?? .leonida
    }
}

/// Les champs pipeline-only du schéma (`status`, `sources`, `confidence`,
/// `processedFrom`, `sourceClaim`) sont absents ici : Codable ignore
/// silencieusement les clés JSON inconnues au décodage.
struct NewsItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: NewsCategory
    let title: LocalizedText
    let body: LocalizedText
    let publishedAt: String

    /// Absent des entrées publiées avant l'ouverture du fil aux deux jeux :
    /// elles portaient toutes sur celui à venir, d'où le défaut.
    let game: NewsGame

    private enum CodingKeys: String, CodingKey {
        case id, category, title, body, publishedAt, game
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(NewsCategory.self, forKey: .category)
        title = try container.decode(LocalizedText.self, forKey: .title)
        body = try container.decode(LocalizedText.self, forKey: .body)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        game = try container.decodeIfPresent(NewsGame.self, forKey: .game) ?? .leonida
    }

    init(
        id: String,
        category: NewsCategory,
        title: LocalizedText,
        body: LocalizedText,
        publishedAt: String,
        game: NewsGame = .leonida
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.publishedAt = publishedAt
        self.game = game
    }
}
