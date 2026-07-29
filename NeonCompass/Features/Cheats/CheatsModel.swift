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
    var searchQuery: String = ""
    var activeCategories: Set<CheatCategory>
    private(set) var favoriteCheatIDs: Set<String>

    var activeInputMode: CheatInputMode {
        didSet { defaults.set(activeInputMode.rawValue, forKey: Self.inputModeKey) }
    }

    var activeGame: Game {
        didSet { defaults.set(activeGame.rawValue, forKey: Self.gameKey) }
    }

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
        notifyWidgetFavoriteCheat()
    }

    /// Dans l'ordre de l'énumération, pour que le groupe des codes
    /// indisponibles propose toujours ses modes dans le même ordre.
    func modesAvailable(for cheat: Cheat) -> [CheatInputMode] {
        CheatInputMode.allCases.filter { cheat.codes[$0] != nil }
    }

    /// Les triches du jeu actif qui passent catégories et recherche, sans égard
    /// au mode de saisie. Les deux collections publiques en dérivent, pour
    /// qu'aucune triche ne puisse tomber dans les deux ni dans aucune.
    private var matching: [Cheat] {
        let languageCode = currentLanguageCode
        return cheats.filter { cheat in
            cheat.game == activeGame
                && activeCategories.contains(cheat.category)
                && (searchQuery.isEmpty
                    || cheat.effect.resolved(for: languageCode)
                        .localizedCaseInsensitiveContains(searchQuery))
        }
    }

    /// Groupé par catégorie, dans l'ordre de déclaration de l'énumération —
    /// pas dans l'ordre alphabétique d'une langue, qui changerait la mise en
    /// page d'une locale à l'autre. Les catégories vides ne produisent pas de
    /// section.
    var sections: [(category: CheatCategory, cheats: [Cheat])] {
        let available = matching.filter { $0.codes[activeInputMode] != nil }
        return CheatCategory.allCases.compactMap { category in
            let group = available
                .filter { $0.category == category }
                .sorted { isFavorite($0) && !isFavorite($1) }
            return group.isEmpty ? nil : (category, group)
        }
    }

    /// Ce que le mode actif ne permet pas de saisir. Affiché, pas masqué :
    /// masquer ferait croire que ces triches n'existent pas.
    var unavailableInActiveMode: [Cheat] {
        matching.filter { $0.codes[activeInputMode] == nil }
    }

    /// Les triches affichées, à plat et dans l'ordre où la liste les rend —
    /// c'est-à-dire sections aplaties. Base des positions d'encarts, qui se
    /// comptent sur la colonne entière et non par catégorie : une rubrique de
    /// deux codes n'a pas à porter son propre encart.
    var displayedCheats: [Cheat] {
        sections.flatMap(\.cheats)
    }

    /// Rang de chaque triche dans la colonne, pour que la vue sache où insérer un
    /// encart sans reparcourir la liste à chaque carte.
    var flatIndexByID: [String: Int] {
        Dictionary(
            uniqueKeysWithValues: displayedCheats.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    /// Positions des encarts, même règle que le fil d'actu — deux à cinq cartes
    /// entre deux encarts, jamais après la dernière.
    ///
    /// Déterministes ici, là où le fil les tire une fois et les retient : cette
    /// liste se refiltre à chaque changement de mode, de jeu, de catégorie et à
    /// chaque frappe dans la recherche. Voir `InlineAdPlacement.positions(itemCount:)`.
    var adPositions: Set<Int> {
        InlineAdPlacement.positions(itemCount: displayedCheats.count)
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
