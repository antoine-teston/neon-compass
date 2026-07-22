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

    var activePlatform: Platform {
        didSet { defaults.set(activePlatform.rawValue, forKey: Self.platformKey) }
    }

    private let modelContext: ModelContext
    private let defaults: UserDefaults

    init(cheats: [Cheat], modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.cheats = cheats
        self.modelContext = modelContext
        self.defaults = defaults
        self.activeCategories = Set(CheatCategory.allCases)
        let stored = defaults.string(forKey: Self.platformKey).flatMap(Platform.init(rawValue:))
        self.activePlatform = stored ?? .ps5
    }

    func updateCheats(_ newCheats: [Cheat]) {
        cheats = newCheats
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
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    func toggleFavorite(_ cheat: Cheat) {
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteCheat(cheatID: cheat.id))
        }
        try? modelContext.save()
    }
}
