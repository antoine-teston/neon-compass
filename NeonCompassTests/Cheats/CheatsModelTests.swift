import Testing
import Foundation
import SwiftData
@testable import NeonCompass

@MainActor
struct CheatsModelTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FavoriteCheat.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        d.removePersistentDomain(forName: d.description)
        return d
    }

    private func sampleCheats() -> [Cheat] {
        [
            Cheat(id: "a", category: .weapons, effect: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil),
                  sequence: [.ps5: [.up], .xbox: [.up]], blocksTrophies: false),
            Cheat(id: "b", category: .misc, effect: LocalizedText(en: "Beta", fr: nil, es: nil, it: nil, de: nil),
                  sequence: [.ps5: [.down], .xbox: [.down]], blocksTrophies: true),
        ]
    }

    @Test func defaultPlatformIsPS5() {
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: freshDefaults())
        #expect(model.activePlatform == .ps5)
    }

    @Test func platformPreferencePersistsAcrossInstances() {
        let defaults = freshDefaults()
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: defaults)
        model.activePlatform = .xbox
        let second = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: defaults)
        #expect(second.activePlatform == .xbox)
    }

    @Test func favoritesAreToggleableAndPinnedFirst() {
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: freshDefaults())
        #expect(!model.isFavorite(model.filteredCheats[0]))
        let second = sampleCheats()[1]
        model.toggleFavorite(second)
        #expect(model.isFavorite(second))
        #expect(model.filteredCheats.first?.id == "b")
    }

    @Test func favoriteCheatIDsReflectsToggleImmediately() {
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: freshDefaults())
        let cheat = sampleCheats()[0]
        #expect(!model.favoriteCheatIDs.contains(cheat.id))
        model.toggleFavorite(cheat)
        #expect(model.favoriteCheatIDs.contains(cheat.id))
        model.toggleFavorite(cheat)
        #expect(!model.favoriteCheatIDs.contains(cheat.id))
    }

    @Test func filtersByCategoryAndSearch() {
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: freshDefaults())
        model.activeCategories = [.weapons]
        #expect(model.filteredCheats.map(\.id) == ["a"])
        model.activeCategories = Set(CheatCategory.allCases)
        model.searchQuery = "bet"
        #expect(model.filteredCheats.map(\.id) == ["b"])
    }
}
