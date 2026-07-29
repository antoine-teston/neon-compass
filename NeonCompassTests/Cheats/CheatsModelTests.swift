import Foundation
import SwiftData
import Testing
@testable import NeonCompass

@MainActor
struct CheatsModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: FavoriteCheat.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func defaults(_ name: String) -> UserDefaults {
        let suite = "CheatsModelTests.\(name)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        return store
    }

    private func cheat(
        _ id: String,
        _ category: CheatCategory = .misc,
        game: Game = .reference,
        codes: [CheatInputMode: CheatCode]
    ) -> Cheat {
        Cheat(
            id: id, game: game, category: category,
            effect: LocalizedText(en: id, fr: nil, es: nil, it: nil, de: nil),
            codes: codes, blocksTrophies: false
        )
    }

    private func model(_ cheats: [Cheat], defaults store: UserDefaults) throws -> CheatsModel {
        CheatsModel(cheats: cheats, modelContext: try makeContext(), defaults: store)
    }

    // MARK: - Mode de saisie

    // La clé « ps5 » stockée par l'ancienne version doit continuer à se lire :
    // un renommage sec renverrait tout le monde au mode par défaut, et le
    // joueur qui avait choisi PlayStation retrouverait le téléphone sans avoir
    // rien touché.
    @Test func migratesTheStoredPS5Platform() throws {
        let store = defaults("migrate-ps5")
        store.set("ps5", forKey: CheatsModel.legacyPlatformKey)
        #expect(try model([], defaults: store).activeInputMode == .playstation)
    }

    @Test func migratesTheStoredXboxPlatform() throws {
        let store = defaults("migrate-xbox")
        store.set("xbox", forKey: CheatsModel.legacyPlatformKey)
        #expect(try model([], defaults: store).activeInputMode == .xbox)
    }

    @Test func firstLaunchLandsOnTheOnlyCompleteMode() throws {
        #expect(try model([], defaults: defaults("fresh")).activeInputMode == .phone)
    }

    @Test func remembersTheChosenMode() throws {
        let store = defaults("remember")
        let sut = try model([], defaults: store)
        sut.activeInputMode = .pc
        #expect(try model([], defaults: store).activeInputMode == .pc)
    }

    // Le nouveau choix prime sur l'ancienne clé : sans ça, quelqu'un qui avait
    // « ps5 » puis choisit le clavier retrouverait la manette au relancement.
    @Test func theNewChoiceWinsOverTheLegacyKey() throws {
        let store = defaults("new-wins")
        store.set("ps5", forKey: CheatsModel.legacyPlatformKey)
        let sut = try model([], defaults: store)
        sut.activeInputMode = .pc
        #expect(try model([], defaults: store).activeInputMode == .pc)
    }

    // MARK: - Jeu actif

    @Test func firstLaunchLandsOnTheGameThatHasCodes() throws {
        #expect(try model([], defaults: defaults("fresh-game")).activeGame == .reference)
    }

    @Test func remembersTheChosenGame() throws {
        let store = defaults("remember-game")
        let sut = try model([], defaults: store)
        sut.activeGame = .leonida
        #expect(try model([], defaults: store).activeGame == .leonida)
    }

    @Test func keepsOnlyTheActiveGame() throws {
        let sut = try model([
            cheat("v", .misc, game: .reference, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("vi", .misc, game: .leonida, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
        ], defaults: defaults("game"))
        sut.activeGame = .reference
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["v"])
        sut.activeGame = .leonida
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["vi"])
    }

    // MARK: - Partition selon le mode actif

    @Test func partitionsOnWhetherTheActiveModeHasACode() throws {
        let padAndPhone = cheat("pad", .player, codes: [
            .playstation: .buttons([.circle]), .phone: .phone(number: "1-999-1", mnemonic: nil),
        ])
        let phoneOnly = cheat("phone-only", .misc, codes: [
            .phone: .phone(number: "1-999-2", mnemonic: nil),
        ])
        let sut = try model([padAndPhone, phoneOnly], defaults: defaults("partition"))

        sut.activeInputMode = .playstation
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["pad"])
        #expect(sut.unavailableInActiveMode.map(\.id) == ["phone-only"])

        sut.activeInputMode = .phone
        #expect(sut.unavailableInActiveMode.isEmpty)
        #expect(sut.sections.flatMap(\.cheats).count == 2)
    }

    // Aucune triche ne doit pouvoir tomber dans les deux collections ni dans
    // aucune : c'est l'invariant que la dérivation depuis un même ensemble filtré
    // existe pour garantir.
    @Test func thePartitionIsExhaustiveAndDisjoint() throws {
        let all = [
            cheat("a", .player, codes: [.playstation: .buttons([.circle]), .phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("b", .misc, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
            cheat("c", .weapons, codes: [.pc: .keyword("X"), .playstation: .buttons([.up])]),
        ]
        let sut = try model(all, defaults: defaults("disjoint"))
        for mode in CheatInputMode.allCases {
            sut.activeInputMode = mode
            let shown = Set(sut.sections.flatMap(\.cheats).map(\.id))
            let hidden = Set(sut.unavailableInActiveMode.map(\.id))
            #expect(shown.isDisjoint(with: hidden), "mode \(mode) : recouvrement")
            #expect(shown.union(hidden) == Set(all.map(\.id)), "mode \(mode) : triche perdue")
        }
    }

    @Test func reportsWhichModesACheatSupports() throws {
        let sut = try model([], defaults: defaults("modes"))
        let c = cheat("x", .misc, codes: [
            .pc: .keyword("X"), .phone: .phone(number: "1-999-1", mnemonic: nil),
        ])
        #expect(sut.modesAvailable(for: c) == [.pc, .phone])
    }

    // MARK: - Sections

    // L'ordre suit la déclaration de l'énumération, pas l'ordre d'arrivée du
    // contenu ni l'alphabet d'une langue — sinon la mise en page change d'une
    // locale à l'autre. Les entrées sont fournies dans l'ordre inverse exprès.
    @Test func groupsByCategoryInDeclarationOrder() throws {
        let sut = try model([
            cheat("m", .misc, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("v", .vehicles, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
            cheat("p", .player, codes: [.phone: .phone(number: "1-999-3", mnemonic: nil)]),
        ], defaults: defaults("sections"))
        #expect(sut.sections.map(\.category) == [.player, .vehicles, .misc])
        #expect(sut.sections.map(\.cheats.count) == [1, 1, 1])
    }

    @Test func emptyCategoriesProduceNoSection() throws {
        let sut = try model([
            cheat("m", .misc, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
        ], defaults: defaults("no-empty"))
        #expect(sut.sections.count == 1)
    }

    // MARK: - Recherche et filtres

    @Test func searchMatchesTheEffectText() throws {
        let sut = try model([
            cheat("comet", .vehicles, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("kraken", .vehicles, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
        ], defaults: defaults("search"))
        sut.searchQuery = "krak"
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["kraken"])
    }

    // La recherche doit aussi porter sur les codes indisponibles : chercher une
    // triche et ne rien trouver parce qu'elle est reléguée dans le groupe replié
    // serait pire que de ne pas la filtrer du tout.
    @Test func searchAlsoFiltersTheUnavailableGroup() throws {
        let sut = try model([
            cheat("kraken", .vehicles, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("comet", .vehicles, codes: [.playstation: .buttons([.circle])]),
        ], defaults: defaults("search-unavailable"))
        sut.activeInputMode = .playstation
        sut.searchQuery = "krak"
        #expect(sut.unavailableInActiveMode.map(\.id) == ["kraken"])
        #expect(sut.sections.flatMap(\.cheats).isEmpty)
    }

    @Test func filtersByCategory() throws {
        let sut = try model([
            cheat("a", .weapons, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("b", .misc, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
        ], defaults: defaults("categories"))
        sut.activeCategories = [.weapons]
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["a"])
    }

    // MARK: - État d'attente

    @Test func awaitsContentForAGameThatHasNoCodes() throws {
        let sut = try model([
            cheat("v", .misc, game: .reference, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
        ], defaults: defaults("await"))
        #expect(!sut.isAwaitingContent)
        sut.activeGame = .leonida
        #expect(sut.isAwaitingContent)
    }

    // La distinction qui compte : « ce jeu n'a pas encore de codes » n'est pas
    // « ta recherche ne trouve rien ». Afficher le premier pour le second serait
    // un mensonge.
    @Test func aFruitlessSearchIsNotAnAbsenceOfContent() throws {
        let sut = try model([
            cheat("comet", .vehicles, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
        ], defaults: defaults("await-search"))
        sut.searchQuery = "rienquicorresponde"
        #expect(sut.sections.isEmpty)
        #expect(!sut.isAwaitingContent)
    }

    // Un mode de saisie qui ne couvre rien n'est pas non plus une absence de
    // contenu : le groupe des codes indisponibles a de quoi s'afficher.
    @Test func aModeThatCoversNothingIsNotAnAbsenceOfContent() throws {
        let sut = try model([
            cheat("phone-only", .misc, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
        ], defaults: defaults("await-mode"))
        sut.activeInputMode = .xbox
        #expect(sut.sections.isEmpty)
        #expect(!sut.unavailableInActiveMode.isEmpty)
        #expect(!sut.isAwaitingContent)
    }

    // MARK: - Favoris (repris de la version précédente du fichier)

    private var favoritable: [Cheat] {
        [
            cheat("a", .weapons, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("b", .weapons, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
        ]
    }

    @Test func favoritesAreToggleableAndPinnedFirst() throws {
        let sut = try model(favoritable, defaults: defaults("fav-pinned"))
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["a", "b"])
        sut.toggleFavorite(favoritable[1])
        #expect(sut.sections.flatMap(\.cheats).first?.id == "b")
    }

    @Test func favoriteCheatIDsReflectsToggleImmediately() throws {
        let sut = try model(favoritable, defaults: defaults("fav-ids"))
        let target = favoritable[0]
        #expect(!sut.favoriteCheatIDs.contains(target.id))
        sut.toggleFavorite(target)
        #expect(sut.favoriteCheatIDs.contains(target.id))
        sut.toggleFavorite(target)
        #expect(!sut.favoriteCheatIDs.contains(target.id))
    }
}
