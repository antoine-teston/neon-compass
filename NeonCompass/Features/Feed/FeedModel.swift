import Foundation
import Observation

@Observable
@MainActor
final class FeedModel {
    private(set) var newsItems: [NewsItem]

    /// Ce sur quoi le fil est restreint.
    ///
    /// En lecture seule de l'extérieur, et non un `var` lié à la vue : la
    /// réconciliation ci-dessous MUTE le filtre, donc un `didSet` chargé de
    /// recalculer se rappellerait lui-même. Les deux méthodes de sélection sont
    /// la seule porte d'entrée.
    private(set) var filter: FeedFilter = .all

    /// L'entrée mise en avant : la plus récente de ce qui est visible.
    ///
    /// La récence est le SEUL signal de hiérarchie que porte le contenu. On a
    /// regardé les autres : dix-sept des quarante-six entrées publiées sont des
    /// annonces officielles sur le jeu à venir, donc ni la rubrique ni le niveau
    /// de confiance ne distinguent quoi que ce soit.
    private(set) var featuredItem: NewsItem?

    /// Le reste du fil, groupé par tranche de temps. L'entrée à la une en est
    /// retirée : elle est déjà affichée au-dessus, et un en-tête de période
    /// posé par-dessus lui retirerait précisément son statut de une.
    private(set) var sections: [FeedSection] = []

    /// Nombre d'entrées visibles hors celle à la une — ce sur quoi les encarts
    /// sont positionnés.
    private(set) var listedItemCount: Int = 0

    private(set) var availableGames: [Game] = []
    private(set) var availableCategories: [NewsCategory] = []

    /// Les entrées parues depuis la dernière session, figées.
    ///
    /// Figées et non recalculées à la volée : le magasin est mis à jour dès le
    /// premier calcul, donc une propriété dérivée se viderait sous les yeux du
    /// lecteur au premier rendu suivant.
    private(set) var newItemIDs: Set<String> = []

    /// Retenu pour que le fil puisse être rafraîchi à la demande. Optionnel :
    /// les tests construisent le modèle à partir d'entrées nues, sans store ni
    /// SwiftData.
    private let contentStore: ContentStore<NewsItem>?
    private let seenStore: FeedSeenStore
    private let now: () -> Date

    /// Capturé UNE FOIS à la construction, avant tout enregistrement.
    ///
    /// Sans cette capture, `hasRecordedASession` deviendrait vrai dès le premier
    /// calcul de cette session, et la synchronisation qui suit le lancement
    /// marquerait tout le fil comme neuf au premier démarrage.
    private let hadPreviousSession: Bool

    init(
        newsItems: [NewsItem],
        contentStore: ContentStore<NewsItem>? = nil,
        seenStore: FeedSeenStore = FeedSeenStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.newsItems = Self.sortedByMostRecent(newsItems)
        self.contentStore = contentStore
        self.seenStore = seenStore
        self.now = now
        self.hadPreviousSession = seenStore.hasRecordedASession
        markNewItems()
        recomputeDerivedState()
    }

    /// Index des cartes après lesquelles un encart publicitaire s'intercale.
    ///
    /// Tiré ICI et pas dans la vue, et c'est tout l'enjeu : un tirage refait à
    /// chaque évaluation du corps de la vue déplacerait les encarts au moindre
    /// rendu — un défilement, une rotation, un changement d'abonnement — et le
    /// fil sauterait sous le doigt. Le tirage ne change qu'avec ce qui est
    /// affiché, donc aussi quand un filtre est posé : ce n'est plus le même fil.
    private(set) var adPositions: Set<Int> = []

    func updateNewsItems(_ newItems: [NewsItem]) {
        newsItems = Self.sortedByMostRecent(newItems)
        markNewItems()
        recomputeDerivedState()
    }

    // MARK: - Filtres

    /// Changer de jeu peut retirer la rubrique sélectionnée du choix : la
    /// réconciliation vit dans le recalcul, qui la relâche alors.
    func selectGame(_ game: Game?) {
        guard filter.game != game else { return }
        filter.game = game
        recomputeDerivedState()
    }

    func selectCategory(_ category: NewsCategory?) {
        guard filter.category != category else { return }
        filter.category = category
        recomputeDerivedState()
    }

    /// Tirer-pour-rafraîchir. Contrairement à la synchronisation de lancement,
    /// force la lecture même si la version n'a pas bougé : quelqu'un qui tire
    /// sur l'écran demande une vérification, pas une consultation de cache.
    ///
    /// L'échec est silencieux, comme au lancement : le geste rend la main, le
    /// fil garde ce qu'il affichait. Un fil qui se vide parce que le réseau a
    /// hoqueté serait pire que pas de rafraîchissement du tout.
    func refresh() async {
        guard let contentStore else { return }
        try? await contentStore.refresh()
        updateNewsItems(contentStore.items)
    }

    // MARK: - État dérivé

    private func recomputeDerivedState() {
        availableGames = FeedFiltering.availableGames(in: newsItems)

        // Les rubriques proposées dépendent du jeu choisi. Passer de VI à V peut
        // donc retirer la rubrique sélectionnée — auquel cas elle est relâchée
        // plutôt que de rendre un fil vide sous une puce active. Idem si une
        // publication fait disparaître la dernière entrée d'une rubrique.
        availableCategories = FeedFiltering.availableCategories(in: newsItems, game: filter.game)
        if let category = filter.category, !availableCategories.contains(category) {
            filter.category = nil
        }

        let visible = FeedFiltering.apply(filter, to: newsItems)
        featuredItem = visible.first
        let listed = Array(visible.dropFirst())
        listedItemCount = listed.count
        sections = FeedFiltering.sections(from: listed, now: now())

        adPositions = InlineAdPlacement.positions(itemCount: listed.count)
    }

    /// Compare le fil complet — pas le fil filtré — au magasin, puis enregistre.
    ///
    /// Sur le fil complet, sans quoi poser un filtre effacerait le repère des
    /// entrées qu'il masque : elles seraient enregistrées comme vues sans avoir
    /// jamais été affichées.
    private func markNewItems() {
        let currentIDs = Set(newsItems.map(\.id))
        if hadPreviousSession {
            // Union et non remplacement : une entrée arrivée par une
            // synchronisation en cours de session reste signalée jusqu'à la
            // prochaine, comme celles trouvées au lancement.
            newItemIDs.formUnion(currentIDs.subtracting(seenStore.seenIDs))
        }
        seenStore.record(currentIDs)
    }

    private static func sortedByMostRecent(_ items: [NewsItem]) -> [NewsItem] {
        // `publishedAt` — la date que la carte AFFICHE. Une liste s'ordonne sur
        // ce qu'elle montre, sinon elle se lit comme cassée.
        //
        // Le fil s'est ordonné sur `listedAt` (jour de mise en ligne) du
        // 2026-08-17 au 2026-08-19. L'intention était bonne : une actu récoltée
        // le 10 et mise en ligne le 17 ne devait pas naître sous des cartes déjà
        // lues. Mais elle supposait que les deux dates restent proches, et
        // publier d'un coup un mois d'arriéré les a écartées de trente jours —
        // 46 cartes datées du 19 juillet au 18 août rangées sous « cette
        // semaine », et les dates qui remontent quand on descend la liste.
        //
        // Ce qui a tranché : `listedAt` protégeait d'un ARRIÉRÉ DE BROUILLONS,
        // et cet arriéré n'existe plus — la veille publie le jour même depuis la
        // même date. Le garde-fou ne protégeait plus de rien et produisait le
        // désordre qu'il devait empêcher. `listedAt` reste décodé, il n'ordonne
        // plus rien.
        //
        // Départage sur `id`, et il n'est pas cosmétique : `sorted(by:)` n'est
        // pas stable, et le fil porte régulièrement plusieurs actus du même jour
        // — trois cartes du 3 août coexistaient au 2026-08-19. Sans critère
        // total, leur ordre change d'un tri à l'autre, donc la liste se
        // réordonne sous le doigt après un tirer-pour-rafraîchir sans qu'aucun
        // contenu ait bougé. Les dates sont en aaaa-mm-jj, donc l'ordre
        // lexicographique EST l'ordre chronologique.
        items.sorted { ($0.publishedAt, $0.id) > ($1.publishedAt, $1.id) }
    }
}
