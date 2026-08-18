import Foundation

/// Ce sur quoi le fil est restreint. `nil` sur une dimension = pas de
/// restriction sur celle-ci.
struct FeedFilter: Equatable, Sendable {
    var game: Game?
    var category: NewsCategory?

    static let all = FeedFilter(game: nil, category: nil)
}

/// La tranche de temps sous laquelle une entrée se range.
///
/// Trois paliers et pas douze : un en-tête par mois donnerait autant de titres
/// que de cartes sur un fil qui publie deux ou trois brèves par semaine. Ce qui
/// intéresse un lecteur, c'est « est-ce de cette semaine ? », pas la date exacte
/// — celle-ci est déjà sur la carte.
enum FeedPeriod: String, CaseIterable, Identifiable, Sendable {
    case thisWeek
    case thisMonth
    case earlier

    var id: String { rawValue }
}

/// Une tranche du fil et son en-tête.
struct FeedSection: Identifiable, Equatable, Sendable {
    let period: FeedPeriod
    let items: [NewsItem]

    var id: String { period.rawValue }
}

/// Le filtrage et le groupement du fil, sans SwiftUI ni état.
///
/// Séparé de `FeedModel` parce que ce sont les seules règles du fil qu'on veut
/// pouvoir éprouver sur des cas limites — un fil vide, une date illisible, une
/// rubrique que le jeu sélectionné ne contient pas — sans monter de modèle.
enum FeedFiltering {
    static func apply(_ filter: FeedFilter, to items: [NewsItem]) -> [NewsItem] {
        items.filter { item in
            if let game = filter.game, item.game != game { return false }
            if let category = filter.category, item.category != category { return false }
            return true
        }
    }

    /// Les rubriques qui rendront au moins une carte pour ce jeu.
    ///
    /// C'est ce qui garantit qu'aucune combinaison de filtres n'aboutit à un fil
    /// vide : une rubrique qu'on ne peut pas choisir ne peut pas décevoir. L'ordre
    /// vient de `allCases` et non du contenu, sans quoi les puces changeraient de
    /// place d'une publication à l'autre.
    static func availableCategories(in items: [NewsItem], game: Game?) -> [NewsCategory] {
        let scoped = apply(FeedFilter(game: game, category: nil), to: items)
        let present = Set(scoped.map(\.category))
        return NewsCategory.allCases.filter { present.contains($0) }
    }

    /// Les jeux effectivement représentés, dans l'ordre de `allCases`.
    ///
    /// Le fil a longtemps été mono-jeu : tant qu'une seule valeur est présente,
    /// proposer de filtrer dessus est un choix sans conséquence, donc du bruit.
    static func availableGames(in items: [NewsItem]) -> [Game] {
        let present = Set(items.map(\.game))
        guard present.count > 1 else { return [] }
        return Game.allCases.filter { present.contains($0) }
    }

    /// Regroupe des entrées DÉJÀ triées par date décroissante. Le groupement
    /// préserve cet ordre au sein de chaque tranche, et les tranches vides
    /// disparaissent plutôt que d'afficher un en-tête sans rien dessous.
    static func sections(from items: [NewsItem], now: Date, calendar: Calendar = .current) -> [FeedSection] {
        var buckets: [FeedPeriod: [NewsItem]] = [:]
        for item in items {
            buckets[period(of: item, now: now, calendar: calendar), default: []].append(item)
        }
        return FeedPeriod.allCases.compactMap { period in
            guard let items = buckets[period], !items.isEmpty else { return nil }
            return FeedSection(period: period, items: items)
        }
    }

    /// Une date illisible retombe sur « plus tôt » plutôt que de faire
    /// disparaître l'entrée : le fil ne doit jamais perdre une carte à cause du
    /// format d'un champ.
    ///
    /// Une date FUTURE compte comme cette semaine — le contenu est daté au jour,
    /// et une entrée publiée depuis un autre fuseau peut légitimement être datée
    /// de demain.
    private static func period(of item: NewsItem, now: Date, calendar: Calendar) -> FeedPeriod {
        guard let date = item.arrivalDate else { return .earlier }
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: start, to: today).day else { return .earlier }
        switch days {
        case ..<7: return .thisWeek
        case ..<30: return .thisMonth
        default: return .earlier
        }
    }
}

extension NewsItem {
    /// `publishedAt` est une date ISO courte, pas un `Date` : c'est ce qui garde
    /// le `JSONDecoder` du `ContentStore` générique libre de toute stratégie de
    /// date. La conversion ne concerne que l'affichage et le groupement, et une
    /// chaîne inattendue rend `nil` plutôt que de faire tomber la carte.
    ///
    /// Celle-ci est la date AFFICHÉE — la carte et la vue de détail. Le
    /// groupement, lui, passe par `arrivalDate`.
    var publishedDate: Date? {
        Self.isoFormatter.date(from: publishedAt)
    }

    /// La date d'apparition dans le fil, sur laquelle les tranches se calculent.
    ///
    /// Distincte de `publishedDate` par le champ qu'elle lit, identique par tout
    /// le reste — même formateur, donc même fuseau, sans quoi les deux dates
    /// d'une même entrée pourraient tomber de part et d'autre d'un minuit.
    var arrivalDate: Date? {
        Self.isoFormatter.date(from: arrivedAt)
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
