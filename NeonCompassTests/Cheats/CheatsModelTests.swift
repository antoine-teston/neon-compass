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

    // MARK: - Filtre par rubrique

    /// Le téléphone : c'est le mode par défaut, et le seul où les 36 codes
    /// existent tous — une liste filtrée par rubrique ne doit pas se vider parce
    /// que le mode de saisie manque.
    private func sampleCodes() -> [CheatInputMode: CheatCode] {
        [.phone: .phone(number: "1-999-0", mnemonic: nil)]
    }

    @Test func selectingACategoryRestrictsTheList() throws {
        let store = defaults(#function)
        let sut = try model([
            cheat("a", .weapons, codes: sampleCodes()),
            cheat("b", .vehicles, codes: sampleCodes()),
            cheat("c", .weapons, codes: sampleCodes())
        ], defaults: store)

        #expect(sut.selectedCategory == nil)
        #expect(sut.displayedCheats.count == 3)

        sut.selectCategory(.weapons)
        #expect(sut.displayedCheats.map(\.id).sorted() == ["a", "c"])

        sut.selectCategory(nil)
        #expect(sut.displayedCheats.count == 3)
    }

    /// Aucune puce ne doit pouvoir rendre une liste vide.
    @Test func onlyOffersCategoriesThatWouldReturnSomething() throws {
        let store = defaults(#function)
        let sut = try model([
            cheat("a", .weapons, codes: sampleCodes()),
            cheat("b", .vehicles, codes: sampleCodes())
        ], defaults: store)

        // L'ordre vient de `allCases`, pas du contenu : sinon les puces
        // changeraient de place d'une publication à l'autre.
        #expect(sut.availableCategories == [.weapons, .vehicles])
    }

    @Test func changingGameReleasesACategoryTheNewGameDoesNotHave() throws {
        let store = defaults(#function)
        let sut = try model([
            cheat("a", .weapons, game: .reference, codes: sampleCodes()),
            cheat("b", .vehicles, game: .leonida, codes: sampleCodes())
        ], defaults: store)

        sut.selectCategory(.weapons)
        #expect(sut.selectedCategory == .weapons)

        sut.activeGame = .leonida
        // « Armes » n'existe pas pour ce jeu : la rubrique est relâchée plutôt
        // que de rendre zéro carte sous une puce allumée.
        #expect(sut.selectedCategory == nil)
        #expect(sut.displayedCheats.map(\.id) == ["b"])
    }

    @Test func changingGameKeepsACategoryTheNewGameAlsoHas() throws {
        let store = defaults(#function)
        let sut = try model([
            cheat("a", .weapons, game: .reference, codes: sampleCodes()),
            cheat("b", .weapons, game: .leonida, codes: sampleCodes())
        ], defaults: store)

        sut.selectCategory(.weapons)
        sut.activeGame = .leonida
        #expect(sut.selectedCategory == .weapons)
        #expect(sut.displayedCheats.map(\.id) == ["b"])
    }

    /// `activeCategories` DÉRIVE de la sélection : deux états à tenir en accord
    /// finiraient par diverger.
    @Test func activeCategoriesDerivesFromTheSelection() throws {
        let store = defaults(#function)
        let sut = try model([cheat("a", .weapons, codes: sampleCodes())], defaults: store)

        #expect(sut.activeCategories == Set(CheatCategory.allCases))
        sut.selectCategory(.weapons)
        #expect(sut.activeCategories == [.weapons])
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
    //
    // Le modèle REÇOIT le jeu, il ne le détient plus : la bascule vit dans la
    // barre haute et son état dans `AppModel`. Le premier lancement et la
    // mémoire du choix se vérifient donc dans `AppModelGameTests`. Ce qui reste
    // ici est ce que le modèle est seul à savoir faire du jeu qu'on lui donne.

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
        sut.selectCategory(.weapons)
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["a"])
    }

    // MARK: - Colonne à plat et encarts

    // Les encarts se comptent sur la colonne entière, pas par rubrique : une
    // catégorie de deux codes n'a pas à porter son propre encart. L'index doit
    // donc traverser les sections, pas repartir de zéro à chacune.
    @Test func theFlatIndexSpansSectionsRatherThanRestarting() throws {
        let sut = try model([
            cheat("p1", .player, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
            cheat("p2", .player, codes: [.phone: .phone(number: "1-999-2", mnemonic: nil)]),
            cheat("w1", .weapons, codes: [.phone: .phone(number: "1-999-3", mnemonic: nil)]),
            cheat("v1", .vehicles, codes: [.phone: .phone(number: "1-999-4", mnemonic: nil)]),
        ], defaults: defaults("flat-index"))

        #expect(sut.displayedCheats.map(\.id) == ["p1", "p2", "w1", "v1"])
        let index = sut.flatIndexByID
        #expect(index["p1"] == 0)
        #expect(index["p2"] == 1)
        #expect(index["w1"] == 2)
        #expect(index["v1"] == 3)
    }

    @Test func theFlatIndexCoversExactlyTheDisplayedCheats() throws {
        let sut = try model([
            cheat("shown", .player, codes: [.playstation: .buttons([.circle])]),
            cheat("hidden", .misc, codes: [.phone: .phone(number: "1-999-1", mnemonic: nil)]),
        ], defaults: defaults("flat-covers"))
        sut.activeInputMode = .playstation
        #expect(sut.flatIndexByID.keys.sorted() == ["shown"])
    }

    // Recalculées à chaque évaluation du corps de la vue : si elles n'étaient pas
    // stables, les encarts changeraient de place au moindre rendu.
    @Test func adPositionsAreStableAcrossEvaluations() throws {
        let sut = try model(
            (1...12).map { cheat("c\($0)", .player, codes: [.phone: .phone(number: "1-999-\($0)", mnemonic: nil)]) },
            defaults: defaults("ads-stable")
        )
        let first = sut.adPositions
        #expect(sut.adPositions == first)
        #expect(sut.adPositions == first)
        #expect(!first.isEmpty)
    }

    @Test func adPositionsNeverPointPastTheDisplayedList() throws {
        let sut = try model(
            (1...12).map { cheat("c\($0)", .player, codes: [.phone: .phone(number: "1-999-\($0)", mnemonic: nil)]) },
            defaults: defaults("ads-bounds")
        )
        let count = sut.displayedCheats.count
        for position in sut.adPositions {
            #expect(position < count - 1)
        }
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

    /// Une carte, un endroit : sans filtre, un favori QUITTE sa rubrique pour la
    /// section des favoris. L'y laisser en plus serait l'afficher deux fois.
    @Test func aFavoriteLeavesItsCategoryForTheFavoritesSection() throws {
        let sut = try model(favoritable, defaults: defaults("fav-section"))
        #expect(sut.favoriteSection.isEmpty)
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["a", "b"])

        sut.toggleFavorite(favoritable[1])
        #expect(sut.favoriteSection.map(\.id) == ["b"])
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["a"])
    }

    /// Sous filtre de rubrique, en revanche, c'est cette rubrique qu'on regarde :
    /// le favori y reste, et remonte en tête.
    @Test func underACategoryFilterTheFavoriteStaysAndLeads() throws {
        let sut = try model(favoritable, defaults: defaults("fav-under-filter"))
        sut.toggleFavorite(favoritable[1])
        sut.select(.category(.weapons))

        #expect(sut.favoriteSection.isEmpty)
        #expect(sut.sections.flatMap(\.cheats).map(\.id) == ["b", "a"])
    }

    /// Sous « Favoris », la carte porte tout et les rubriques ne rendent rien :
    /// les mêmes codes aux deux endroits seraient un doublon.
    @Test func theFavoritesFilterLeavesEverythingToTheCard() throws {
        let sut = try model(favoritable, defaults: defaults("fav-filter"))
        sut.toggleFavorite(favoritable[1])
        sut.select(.favorites)

        #expect(sut.favoriteSection.map(\.id) == ["b"])
        #expect(sut.displayedCheats.isEmpty)
    }

    /// LA raison d'être de la carte : les favoris sortent de la colonne où
    /// `InlineAdPlacement` distribue ses encarts. En section, ils en offraient
    /// des emplacements entre eux ; dans un seul bloc, aucun.
    ///
    /// Ce test remplace son inverse, qui figeait la forme précédente.
    @Test func theFavoritesCardIsOutsideTheAdColumn() throws {
        let sut = try model(favoritable, defaults: defaults("fav-column"))
        sut.toggleFavorite(favoritable[1])
        #expect(sut.favoriteSection.map(\.id) == ["b"])
        #expect(sut.displayedCheats.map(\.id) == ["a"])
        #expect(sut.flatIndexByID["b"] == nil)
    }

    /// Sous le filtre « Favoris », aucun encart — et par le bon mécanisme : la
    /// carte porte tout, donc la colonne est VIDE, donc il n'y a nulle part où
    /// poser une bannière. C'est `displayedCheats.isEmpty` qui porte la preuve ;
    /// l'assertion sur `adPositions` seule serait creuse, ce qu'une garde
    /// explicite retirée du modèle a démontré.
    ///
    /// Ce qu'il attrape : quiconque redonnerait des lignes de colonne aux favoris
    /// — un retour à la section — rouvrirait les annonces entre eux.
    @Test func theFavoritesFilterCarriesNoAds() throws {
        let many = (0..<40).map {
            cheat("m\($0)", .misc, codes: [.phone: .phone(number: "1-999-\($0)", mnemonic: nil)])
        }
        let sut = try model(many, defaults: defaults("fav-no-ads"))
        // Quarante cartes : la colonne en porte forcément, c'est ce qui rend le
        // zéro d'après attribuable au filtre et non à la brièveté de la liste.
        #expect(!sut.adPositions.isEmpty)

        for cheat in many.prefix(5) { sut.toggleFavorite(cheat, isProEntitled: false) }
        sut.select(.favorites)
        #expect(sut.adPositions.isEmpty)
        #expect(sut.favoriteSection.count == 5)
        #expect(sut.displayedCheats.isEmpty)
    }

    // MARK: - Plafond des favoris

    private func fiveFavoritable() -> [Cheat] {
        (0..<6).map {
            cheat("f\($0)", .misc, codes: [.phone: .phone(number: "1-999-\($0)", mnemonic: nil)])
        }
    }

    @Test func theSixthFavoriteIsRefusedWithoutPro() throws {
        let all = fiveFavoritable()
        let sut = try model(all, defaults: defaults("fav-cap"))
        for cheat in all.prefix(5) {
            #expect(sut.toggleFavorite(cheat, isProEntitled: false))
        }
        #expect(sut.isAtFavoriteCap(isProEntitled: false))
        #expect(!sut.toggleFavorite(all[5], isProEntitled: false))
        #expect(sut.favoriteCount == CheatsModel.freeFavoriteCap)
        #expect(!sut.isFavorite(all[5]))
    }

    @Test func proHasNoCap() throws {
        let all = fiveFavoritable()
        let sut = try model(all, defaults: defaults("fav-cap-pro"))
        for cheat in all {
            #expect(sut.toggleFavorite(cheat, isProEntitled: true))
        }
        #expect(sut.favoriteCount == 6)
        #expect(!sut.isAtFavoriteCap(isProEntitled: true))
    }

    /// Le plafond bloque l'AJOUT, il ne supprime rien. Quelqu'un qui avait plus
    /// de cinq favoris avant qu'il existe les garde, et peut en retirer jusqu'à
    /// repasser sous la barre — sans quoi une règle apparue après coup
    /// détruirait ce qu'il avait rangé.
    @Test func beyondTheCapNothingIsTakenAwayAndRemovingStillWorks() throws {
        let all = fiveFavoritable()
        let sut = try model(all, defaults: defaults("fav-cap-legacy"))
        for cheat in all { sut.toggleFavorite(cheat, isProEntitled: true) }
        #expect(sut.favoriteCount == 6)

        // Passé en gratuit : rien n'est rogné.
        #expect(sut.isAtFavoriteCap(isProEntitled: false))
        #expect(sut.favoriteCount == 6)

        // Retirer reste permis, et ramène sous la barre.
        #expect(sut.toggleFavorite(all[0], isProEntitled: false))
        #expect(sut.toggleFavorite(all[1], isProEntitled: false))
        #expect(sut.favoriteCount == 4)
        #expect(!sut.isAtFavoriteCap(isProEntitled: false))
        #expect(sut.toggleFavorite(all[0], isProEntitled: false))
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
