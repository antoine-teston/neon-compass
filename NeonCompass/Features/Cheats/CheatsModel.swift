import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CheatsModel {
    private static let platformKey = "cheatsActivePlatform"

    private(set) var cheats: [Cheat]
    var searchQuery: String = ""
    var activeCategories: Set<CheatCategory>
    private(set) var favoriteCheatIDs: Set<String>

    var activePlatform: Platform {
        didSet { defaults.set(activePlatform.rawValue, forKey: Self.platformKey) }
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
        self.favoriteCheatIDs = Set((try? modelContext.fetch(FetchDescriptor<FavoriteCheat>()))?.map(\.cheatID) ?? [])
        let stored = defaults.string(forKey: Self.platformKey).flatMap(Platform.init(rawValue:))
        self.activePlatform = stored ?? .ps5
        notifyWidgetFavoriteCheat()
    }

    func updateCheats(_ newCheats: [Cheat]) {
        cheats = newCheats
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

    var filteredCheats: [Cheat] {
        let languageCode = currentLanguageCode
        let matching = cheats.filter { cheat in
            activeCategories.contains(cheat.category)
                && (searchQuery.isEmpty
                    || cheat.effect.resolved(for: languageCode).localizedCaseInsensitiveContains(searchQuery))
        }
        return matching.sorted { isFavorite($0) && !isFavorite($1) }
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
}
