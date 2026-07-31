import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CheatsModel {
    private static let inputModeKey = "cheatsActiveInputMode"
    private static let gameKey = "cheatsActiveGame"
    /// Clé de l'époque où le sélecteur portait sur une plate-forme et non sur un
    /// mode de saisie. Lue une fois, jamais écrite.
    static let legacyPlatformKey = "cheatsActivePlatform"

    private(set) var cheats: [Cheat]
    var searchQuery: String = "" {
        didSet { recompute() }
    }
    var activeCategories: Set<CheatCategory> {
        didSet { recompute() }
    }
    private(set) var favoriteCheatIDs: Set<String>

    var activeInputMode: CheatInputMode {
        didSet {
            defaults.set(activeInputMode.rawValue, forKey: Self.inputModeKey)
            recompute()
        }
    }

    var activeGame: Game {
        didSet {
            defaults.set(activeGame.rawValue, forKey: Self.gameKey)
            recompute()
        }
    }

    // MARK: - Vues dérivées, STOCKÉES et non calculées
    //
    // Ces cinq valeurs forment une chaîne : la liste filtrée nourrit les
    // sections, qui nourrissent la colonne à plat, qui nourrit l'index et les
    // positions d'encarts. Tant qu'elles étaient des propriétés calculées,
    // chaque lecture rejouait toute la chaîne depuis le début — et la vue lit
    // `adPositions` UNE FOIS PAR CARTE affichée, ce qui rendait le coût
    // quadratique.
    //
    // Mesuré à la sonde avant correction : une seule évaluation du corps de la
    // liste déclenchait 23 filtrages complets du catalogue, chacun portant une
    // comparaison sensible à la locale. Et l'ensemble se rejouait à chaque
    // frappe dans la recherche.
    //
    // Le fil d'actu résolvait déjà ce problème de cette exacte façon (cf.
    // `FeedModel.adPositions`) : on aligne l'écran Codes sur la convention que
    // l'autre applique. Le recalcul se fait aux seuls moments où une entrée
    // change — c'est ce que garantissent les `didSet` ci-dessus, plus les
    // appels explicites de `updateCheats` et `toggleFavorite`.
    private(set) var sections: [(category: CheatCategory, cheats: [Cheat])] = []
    private(set) var unavailableInActiveMode: [Cheat] = []
    private(set) var displayedCheats: [Cheat] = []
    private(set) var flatIndexByID: [String: Int] = [:]
    private(set) var adPositions: Set<Int> = []

    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private let widgetSummaryCoordinator: WidgetSummaryCoordinator?

    init(
        cheats: [Cheat],
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        widgetSummaryCoordinator: WidgetSummaryCoordinator? = nil
    ) {
        self.cheats = cheats
        self.modelContext = modelContext
        self.defaults = defaults
        self.widgetSummaryCoordinator = widgetSummaryCoordinator
        self.activeCategories = Set(CheatCategory.allCases)
        self.favoriteCheatIDs = Set(
            (try? modelContext.fetch(FetchDescriptor<FavoriteCheat>()))?.map(\.cheatID) ?? []
        )
        self.activeInputMode = Self.storedInputMode(in: defaults)
        self.activeGame = defaults.string(forKey: Self.gameKey)
            .flatMap(Game.init(rawValue:)) ?? .reference
        // Les `didSet` ne se déclenchent pas pendant l'initialisation : les
        // dérivées seraient restées vides sans cet appel explicite.
        recompute()
        notifyWidgetFavoriteCheat()
    }

    /// La valeur de l'ancienne clé est encore la préférence de l'utilisateur :
    /// « ps5 » désignait déjà la famille PlayStation, dont les combos sont
    /// identiques de la PS3 à la PS5. Un renommage sec renverrait au mode par
    /// défaut quelqu'un qui avait choisi.
    private static func storedInputMode(in defaults: UserDefaults) -> CheatInputMode {
        if let raw = defaults.string(forKey: inputModeKey),
           let mode = CheatInputMode(rawValue: raw) {
            return mode
        }
        switch defaults.string(forKey: legacyPlatformKey) {
        case "ps5": return .playstation
        case "xbox": return .xbox
        default: return .default
        }
    }

    func updateCheats(_ newCheats: [Cheat]) {
        cheats = newCheats
        recompute()
        notifyWidgetFavoriteCheat()
    }

    /// Dans l'ordre de l'énumération, pour que le groupe des codes
    /// indisponibles propose toujours ses modes dans le même ordre.
    func modesAvailable(for cheat: Cheat) -> [CheatInputMode] {
        CheatInputMode.allCases.filter { cheat.codes[$0] != nil }
    }

    /// Reconstruit d'un coup toutes les vues dérivées, en ne filtrant le
    /// catalogue qu'UNE fois. L'ordre des affectations suit la dépendance :
    /// sections → colonne à plat → index → encarts.
    private func recompute() {
        let matching = matchingCheats()
        let available = matching.filter { $0.codes[activeInputMode] != nil }

        // Groupé par catégorie, dans l'ordre de déclaration de l'énumération —
        // pas dans l'ordre alphabétique d'une langue, qui changerait la mise en
        // page d'une locale à l'autre. Les catégories vides ne produisent pas
        // de section.
        sections = CheatCategory.allCases.compactMap { category in
            let group = available
                .filter { $0.category == category }
                .sorted { isFavorite($0) && !isFavorite($1) }
            return group.isEmpty ? nil : (category, group)
        }

        // Ce que le mode actif ne permet pas de saisir. Affiché, pas masqué :
        // masquer ferait croire que ces triches n'existent pas. Dérivé du même
        // ensemble filtré que `sections`, ce qui garantit qu'aucune triche ne
        // tombe dans les deux ni dans aucune.
        unavailableInActiveMode = matching.filter { $0.codes[activeInputMode] == nil }

        // Les encarts se comptent sur la colonne entière et non par catégorie :
        // une rubrique de deux codes n'a pas à porter son propre encart.
        displayedCheats = sections.flatMap(\.cheats)
        flatIndexByID = Dictionary(
            uniqueKeysWithValues: displayedCheats.enumerated().map { ($0.element.id, $0.offset) }
        )
        adPositions = InlineAdPlacement.positions(itemCount: displayedCheats.count)
    }

    /// Les triches du jeu actif qui passent catégories et recherche, sans égard
    /// au mode de saisie. Les deux collections publiques en dérivent, pour
    /// qu'aucune triche ne puisse tomber dans les deux ni dans aucune.
    private func matchingCheats() -> [Cheat] {
        let languageCode = currentLanguageCode
        return cheats.filter { cheat in
            cheat.game == activeGame
                && activeCategories.contains(cheat.category)
                && (searchQuery.isEmpty
                    || cheat.effect.resolved(for: languageCode)
                        .localizedCaseInsensitiveContains(searchQuery))
        }
    }

    /// Le jeu actif n'a aucun code — et non « la recherche ne trouve rien ».
    ///
    /// La distinction est le fond du sujet : afficher « pas encore de codes »
    /// parce qu'une recherche échoue serait un mensonge. D'où la condition sur
    /// `searchQuery`, et d'où la place de ce calcul ici plutôt que dans la vue :
    /// c'est un état dérivé du modèle, et il se teste.
    var isAwaitingContent: Bool {
        searchQuery.isEmpty
            && !cheats.contains { $0.game == activeGame }
    }

    func isFavorite(_ cheat: Cheat) -> Bool {
        favoriteCheatIDs.contains(cheat.id)
    }

    func toggleFavorite(_ cheat: Cheat) {
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            favoriteCheatIDs.remove(cheatID)
        } else {
            modelContext.insert(FavoriteCheat(cheatID: cheat.id))
            favoriteCheatIDs.insert(cheatID)
        }
        try? modelContext.save()
        // Les favoris remontent en tête de leur rubrique : l'ordre des sections
        // en dépend, il faut donc le refaire ici aussi.
        recompute()
        notifyWidgetFavoriteCheat()
    }

    private func notifyWidgetFavoriteCheat() {
        let title = favoriteCheatIDs.first
            .flatMap { favoriteID in cheats.first { $0.id == favoriteID } }
            .map { $0.effect.resolved(for: currentLanguageCode) }
        widgetSummaryCoordinator?.updateFavoriteCheat(title)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
