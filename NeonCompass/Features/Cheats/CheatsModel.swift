import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CheatsModel {
    private static let inputModeKey = "cheatsActiveInputMode"
    /// Clé de l'époque où le sélecteur portait sur une plate-forme et non sur un
    /// mode de saisie. Lue une fois, jamais écrite.
    static let legacyPlatformKey = "cheatsActivePlatform"

    private(set) var cheats: [Cheat]
    var searchQuery: String = "" {
        didSet { recompute() }
    }
    /// Ce que la liste montre.
    ///
    /// UNE énumération et non une rubrique plus un booléen « favoris ». Les trois
    /// cas s'excluent par construction ; deux états côte à côte seraient deux
    /// états à tenir en accord, ce que ce fichier refuse déjà pour
    /// `activeCategories`. Une restriction à la fois se lit aussi d'un coup
    /// d'œil, là où deux commandes demandent de lire les deux.
    private(set) var filter: CheatFilter = .none {
        didSet { recompute() }
    }

    /// Façade sur `filter`, pour ce qui ne connaît que les rubriques.
    var selectedCategory: CheatCategory? {
        if case .category(let category) = filter { return category }
        return nil
    }

    var showsFavoritesOnly: Bool { filter == .favorites }

    var activeCategories: Set<CheatCategory> {
        selectedCategory.map { [$0] } ?? Set(CheatCategory.allCases)
    }

    /// Les rubriques qui rendront au moins un code pour le jeu actif.
    ///
    /// Aucune combinaison ne peut donc rendre une liste vide sous une puce
    /// allumée. L'ordre vient de `allCases` et non du contenu, sans quoi les
    /// puces changeraient de place d'une publication à l'autre.
    var availableCategories: [CheatCategory] {
        let present = Set(cheats.filter { $0.game == activeGame }.map(\.category))
        return CheatCategory.allCases.filter { present.contains($0) }
    }

    func select(_ newFilter: CheatFilter) {
        guard filter != newFilter else { return }
        filter = newFilter
    }

    /// Façade héritée : une rubrique, ou `nil` pour tout relâcher.
    func selectCategory(_ category: CheatCategory?) {
        select(category.map(CheatFilter.category) ?? .none)
    }

    /// Les favoris posés, mode par mode.
    ///
    /// Un `Set` de couples et non d'identifiants : c'est la clé du magasin, et
    /// c'est ce qui rend « la même triche en favori sur PS mais pas au clavier »
    /// représentable.
    private(set) var favorites: Set<FavoriteKey>

    /// Les favoris du mode actif, en identifiants. Ce que les vues consultent.
    var favoriteCheatIDs: Set<String> {
        let mode = activeInputMode
        return Set(favorites.lazy.filter { $0.mode == mode }.map(\.cheatID))
    }

    var activeInputMode: CheatInputMode {
        didSet {
            defaults.set(activeInputMode.rawValue, forKey: Self.inputModeKey)
            // Changer de mode peut vider les favoris — cinq codes n'ont pas
            // d'équivalent manette — donc le filtre « Favoris » se relâche ici
            // aussi, pas seulement au retrait du dernier favori.
            releaseEmptyFilterOrRecompute()
        }
    }

    /// Le jeu regardé — REÇU, plus détenu.
    ///
    /// La bascule vit dans la barre haute et son état dans `AppModel`, qui le
    /// persiste. `CheatsScreen` pousse ici toute variation. Ce qui reste au
    /// modèle est ce qu'il est seul à savoir faire : relâcher une rubrique que le
    /// nouveau jeu ne propose pas, et recalculer.
    var activeGame: Game {
        didSet {
            // Relâche une rubrique que le nouveau jeu ne propose pas, sans quoi
            // la liste serait vide sous une puce allumée. L'affectation déclenche
            // le recalcul par son propre `didSet` — d'où le `else`, qui évite de
            // le faire deux fois.
            releaseEmptyFilterOrRecompute()
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
    /// Les favoris du jeu et du mode actifs, portés par UNE carte en tête.
    ///
    /// Une carte et non une section de cartes, pour une raison qui n'est pas
    /// d'apparence : une section prend des places dans la colonne, donc des
    /// emplacements d'encarts entre ses éléments. Un seul bloc n'en offre aucun.
    /// Le raccourci qu'on se garde vers ses cinq codes ne se paie pas d'une
    /// bannière au milieu.
    ///
    /// VIDE sous un filtre de RUBRIQUE : on y regarde cette rubrique, et les
    /// favoris qui en font partie y restent, en tête. Sous « Favoris », en
    /// revanche, la carte est tout ce qu'il y a à montrer.
    private(set) var favoriteSection: [Cheat] = []
    private(set) var sections: [(category: CheatCategory, cheats: [Cheat])] = []
    private(set) var unavailableInActiveMode: [Cheat] = []
    private(set) var displayedCheats: [Cheat] = []

    /// L'ordre dans lequel le lecteur plein écran feuillette.
    ///
    /// DISTINCT de `displayedCheats`, et c'est tout le sujet : celui-là est la
    /// colonne sur laquelle les encarts se placent, dont les favoris sont
    /// délibérément absents. Le lecteur, lui, doit pouvoir atteindre TOUT ce que
    /// l'écran montre, carte des favoris comprise.
    ///
    /// Les avoir confondus a coûté un défaut réel : sorti les favoris de la
    /// colonne, taper un favori présentait une pleine page vide — sans même un
    /// bouton pour la refermer, la vue n'étant jamais construite. Deux besoins,
    /// deux propriétés.
    var readableCheats: [Cheat] { favoriteSection + displayedCheats }
    private(set) var flatIndexByID: [String: Int] = [:]
    private(set) var adPositions: Set<Int> = []

    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private let widgetSummaryCoordinator: WidgetSummaryCoordinator?

    init(
        cheats: [Cheat],
        game: Game = .reference,
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        widgetSummaryCoordinator: WidgetSummaryCoordinator? = nil
    ) {
        self.cheats = cheats
        self.modelContext = modelContext
        self.defaults = defaults
        self.widgetSummaryCoordinator = widgetSummaryCoordinator
        let mode = Self.storedInputMode(in: defaults)
        self.favorites = Self.loadFavorites(from: modelContext, adoptingLegacyRowsInto: mode)
        self.activeInputMode = mode
        self.activeGame = game
        // Les `didSet` ne se déclenchent pas pendant l'initialisation : les
        // dérivées seraient restées vides sans cet appel explicite.
        recompute()
        notifyWidgetFavoriteCheat()
    }

    /// Charge les favoris, en ADOPTANT au passage les lignes d'avant la
    /// séparation par mode.
    ///
    /// Ces lignes n'ont pas de mode — le champ est vide. On leur donne celui que
    /// l'utilisateur avait mémorisé : c'est celui sur lequel il les a posées, donc
    /// la seule attribution qui ne perde rien. Les supprimer pour « repartir
    /// propre » reviendrait à effacer ce qu'il avait rangé, et l'alternative
    /// (les faire valoir pour les quatre modes) recréerait exactement le défaut
    /// que la séparation ferme.
    ///
    /// L'écriture se fait une fois : au lancement suivant, plus aucune ligne
    /// n'est vide.
    private static func loadFavorites(
        from context: ModelContext,
        adoptingLegacyRowsInto mode: CheatInputMode
    ) -> Set<FavoriteKey> {
        let rows = (try? context.fetch(FetchDescriptor<FavoriteCheat>())) ?? []
        var adopted = false
        for row in rows where row.inputMode.isEmpty {
            row.inputMode = mode.rawValue
            adopted = true
        }
        if adopted { try? context.save() }
        return Set(
            rows.compactMap { row in
                CheatInputMode(rawValue: row.inputMode)
                    .map { FavoriteKey(cheatID: row.cheatID, mode: $0) }
            }
        )
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

        // Les favoris ne remontent en tête de leur rubrique QUE sous un filtre
        // de rubrique. Sans filtre ils ont leur propre section, et les faire
        // apparaître aux deux endroits serait du bruit.
        switch filter {
        case .none, .favorites:
            favoriteSection = available.filter(isFavorite)
        case .category:
            favoriteSection = []
        }
        // Sous « Favoris » la carte porte tout : les rubriques n'ont plus rien
        // à rendre, sans quoi les mêmes codes paraîtraient deux fois.
        let grouped = filter == .none
            ? available.filter { !isFavorite($0) }
            : (filter == .favorites ? [] : available)

        // Groupé par catégorie, dans l'ordre de déclaration de l'énumération —
        // pas dans l'ordre alphabétique d'une langue, qui changerait la mise en
        // page d'une locale à l'autre. Les catégories vides ne produisent pas
        // de section.
        sections = CheatCategory.allCases.compactMap { category in
            let group = grouped
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
        //
        // Les favoris en sont EXCLUS, et c'est le sens de la carte qui les
        // porte : rassemblés dans un seul bloc, aucune publicité ne peut plus
        // s'intercaler entre eux. Ils avaient d'abord leur propre section, donc
        // leurs propres emplacements d'encarts — c'est précisément ce que cette
        // forme supprime. Le raccourci qu'on se garde vers ses cinq codes ne se
        // paie pas d'une bannière au milieu.
        displayedCheats = sections.flatMap(\.cheats)
        flatIndexByID = Dictionary(
            uniqueKeysWithValues: displayedCheats.enumerated().map { ($0.element.id, $0.offset) }
        )
        // Rien à ajouter pour protéger les favoris du filtre « Favoris » : la
        // carte les porte, `grouped` est vide dans ce cas, donc la colonne l'est
        // aussi et n'offre aucun emplacement. Une garde explicite a été écrite
        // ici puis retirée — elle passait le test en le rendant creux, et le
        // test passait aussi sans elle.
        //
        // La GRAINE est le nombre de triches affichables, favoris COMPRIS, et non
        // la longueur de la colonne. `InlineAdPlacement.positions` sème sur le
        // compte : depuis que les favoris quittent la colonne, favoriter en
        // changeait la longueur, donc la graine, donc TOUTES les positions
        // d'encarts — chaque bannière détruite et recréée sous le doigt, avec sa
        // requête AdMob. Le compte des affichables, lui, ne bouge pas quand on
        // pose une étoile.
        adPositions = InlineAdPlacement.positions(
            itemCount: displayedCheats.count,
            seededBy: available.count
        )
    }

    /// Les triches du jeu actif qui passent catégories et recherche, sans égard
    /// au mode de saisie. Les deux collections publiques en dérivent, pour
    /// qu'aucune triche ne puisse tomber dans les deux ni dans aucune.
    private func matchingCheats() -> [Cheat] {
        let languageCode = currentLanguageCode
        return cheats.filter { cheat in
            cheat.game == activeGame
                && activeCategories.contains(cheat.category)
                && (filter != .favorites || isFavorite(cheat))
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
        favorites.contains(FavoriteKey(cheatID: cheat.id, mode: activeInputMode))
    }

    /// Cinq en gratuit, sans limite en Pro.
    static let freeFavoriteCap = 5

    /// Le compte du plafond : les favoris DU MODE ACTIF, tous jeux confondus, et
    /// seulement ceux qui désignent une triche que le catalogue connaît encore.
    ///
    /// Trois exclusions, trois défauts qu'elles ferment :
    ///
    /// - **Les autres modes.** Cinq codes de GTA V n'ont pas d'équivalent
    ///   manette. Un compte tous modes confondus se remplissait de favoris qu'on
    ///   ne pouvait plus voir ni retirer depuis le mode courant.
    /// - **Les identifiants disparus.** `favorites` est chargé une fois et ne se
    ///   réconcilie pas avec le catalogue ; une publication qui renomme un
    ///   identifiant laisserait sinon une place consommée pour toujours. Rien
    ///   n'est supprimé pour autant — l'identifiant peut revenir.
    /// - Reste ouvert : les deux JEUX partagent le compte, par décision du
    ///   2026-08-10. Le compteur peut donc annoncer cinq au-dessus d'une carte
    ///   qui en montre trois, le jour où le jeu à venir publiera ses codes.
    var favoriteCount: Int {
        let known = Set(cheats.map(\.id))
        return favorites.count { $0.mode == activeInputMode && known.contains($0.cheatID) }
    }

    func isAtFavoriteCap(isProEntitled: Bool) -> Bool {
        !isProEntitled && favoriteCount >= Self.freeFavoriteCap
    }

    /// Y a-t-il un favori que le jeu et le mode actifs sauraient afficher ?
    ///
    /// Ce que la puce « Favoris » doit consulter, et pas `favoriteCount` : celui-ci
    /// compte aussi l'autre jeu. Une puce qui ne rendrait qu'une liste vide est
    /// exactement ce que sa propre documentation dit vouloir éviter.
    ///
    /// Ne peut pas se réduire à `!favoriteSection.isEmpty` : cette collection est
    /// délibérément vide sous un filtre de rubrique, où la puce doit pourtant
    /// rester offerte.
    var hasDisplayableFavorites: Bool {
        cheats.contains { cheat in
            cheat.game == activeGame
                && cheat.codes[activeInputMode] != nil
                && isFavorite(cheat)
        }
    }

    /// Rend `false` quand le plafond a REFUSÉ l'ajout — jamais pour un retrait,
    /// qui est toujours permis. C'est ce que la vue attend pour proposer Pro.
    ///
    /// La règle vit ici et pas dans la vue : une vue ne se teste pas, et il y a
    /// déjà deux endroits d'où l'on étoile une triche — la carte et le lecteur
    /// plein écran.
    ///
    /// `isProEntitled` n'a PAS de valeur par défaut, et c'est délibéré : cet
    /// argument est tout le mécanisme du plafond, et un défaut permissif ferait
    /// qu'un appelant distrait le contournerait sans que rien ne le signale.
    @discardableResult
    func toggleFavorite(_ cheat: Cheat, isProEntitled: Bool) -> Bool {
        let key = FavoriteKey(cheatID: cheat.id, mode: activeInputMode)
        if let existing = storedFavorite(key) {
            modelContext.delete(existing)
            favorites.remove(key)
        } else {
            // Le plafond bloque l'AJOUT, il ne supprime rien. Il n'existait pas
            // jusqu'ici : quelqu'un peut avoir plus de cinq favoris, et les
            // rogner pour tenir dans une règle apparue après coup serait
            // détruire ce qu'il a rangé. Il les garde, et n'en ajoute plus tant
            // qu'il n'est pas repassé sous la barre.
            guard !isAtFavoriteCap(isProEntitled: isProEntitled) else { return false }
            modelContext.insert(FavoriteCheat(cheatID: cheat.id, inputMode: activeInputMode))
            favorites.insert(key)
        }
        try? modelContext.save()
        // Relâche « Favoris » quand il ne reste plus rien à montrer. Sans ça,
        // retirer son dernier favori sous ce filtre laisse un écran sans carte,
        // sans liste et sans état vide — et la puce qui permettrait d'en sortir
        // a disparu en même temps que le dernier favori. Même geste que
        // `activeGame`, qui relâche déjà une rubrique devenue vide.
        releaseEmptyFilterOrRecompute()
        notifyWidgetFavoriteCheat()
        return true
    }

    /// Relâche un filtre que le nouvel état ne peut plus honorer, sinon recalcule.
    ///
    /// UN seul endroit pour les trois entrées — jeu, mode de saisie, retrait d'un
    /// favori. Le relâchement passait auparavant par le seul `didSet` du jeu et ne
    /// couvrait que les rubriques ; « Favoris » lui a échappé, et retirer son
    /// dernier favori sous ce filtre laissait un écran sans carte, sans liste,
    /// sans état vide — et sans la puce qui aurait permis d'en sortir, disparue
    /// avec le dernier favori.
    ///
    /// L'affectation de `filter` déclenche le recalcul par son propre `didSet` —
    /// d'où le `else`, qui évite de le faire deux fois.
    private func releaseEmptyFilterOrRecompute() {
        switch filter {
        case .category(let category) where !availableCategories.contains(category):
            filter = .none
        case .favorites where !hasDisplayableFavorites:
            filter = .none
        default:
            recompute()
        }
    }

    private func storedFavorite(_ key: FavoriteKey) -> FavoriteCheat? {
        let cheatID = key.cheatID
        let mode = key.mode.rawValue
        let descriptor = FetchDescriptor<FavoriteCheat>(
            predicate: #Predicate { $0.cheatID == cheatID && $0.inputMode == mode }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Le widget montre un favori du mode actif — celui qu'on saurait saisir.
    private func notifyWidgetFavoriteCheat() {
        let title = favorites
            .filter { $0.mode == activeInputMode }
            .compactMap { key in cheats.first { $0.id == key.cheatID } }
            .first
            .map { $0.effect.resolved(for: currentLanguageCode) }
        widgetSummaryCoordinator?.updateFavoriteCheat(title)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
