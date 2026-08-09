import Testing
import Foundation
@testable import NeonCompass

@MainActor
struct FeedModelTests {
    private func sampleItem(
        id: String,
        publishedAt: String,
        game: Game = .leonida,
        category: NewsCategory = .announcement
    ) -> NewsItem {
        NewsItem(
            id: id,
            category: category,
            title: LocalizedText(en: "Title \(id)", fr: nil, es: nil, it: nil, de: nil),
            body: LocalizedText(en: "Body \(id)", fr: nil, es: nil, it: nil, de: nil),
            publishedAt: publishedAt,
            game: game
        )
    }

    /// Un magasin par test, jamais `UserDefaults.standard`.
    ///
    /// Le repère de nouveauté persiste par construction : partagé, il ferait
    /// dépendre chaque test de ceux qui l'ont précédé, et le premier à s'exécuter
    /// serait le seul à voir un premier lancement.
    private final class ScratchDefaults {
        let name = "FeedModelTests.\(UUID().uuidString)"
        lazy var defaults = UserDefaults(suiteName: name)!
        deinit { UserDefaults().removePersistentDomain(forName: name) }
    }

    // MARK: - Tri

    @Test func sortsNewsItemsByMostRecentFirst() {
        let scratch = ScratchDefaults()
        let older = sampleItem(id: "a", publishedAt: "2026-07-01")
        let newer = sampleItem(id: "b", publishedAt: "2026-07-20")
        let model = FeedModel(newsItems: [older, newer], seenStore: FeedSeenStore(defaults: scratch.defaults))
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }

    @Test func updateNewsItemsReplacesContentAndResorts() {
        let scratch = ScratchDefaults()
        let model = FeedModel(newsItems: [], seenStore: FeedSeenStore(defaults: scratch.defaults))
        let older = sampleItem(id: "a", publishedAt: "2026-07-01")
        let newer = sampleItem(id: "b", publishedAt: "2026-07-20")
        model.updateNewsItems([older, newer])
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }

    // MARK: - Une et tranches

    @Test func theMostRecentItemIsFeaturedAndNotRepeatedInTheSections() {
        let scratch = ScratchDefaults()
        let items = (1...5).map { sampleItem(id: "\($0)", publishedAt: "2026-08-0\($0)") }
        let model = FeedModel(
            newsItems: items,
            seenStore: FeedSeenStore(defaults: scratch.defaults),
            now: { items[4].publishedDate! }
        )

        #expect(model.featuredItem?.id == "5")
        // Répétée, la une apparaîtrait deux fois de suite à l'écran.
        let listed = model.sections.flatMap(\.items).map(\.id)
        #expect(!listed.contains("5"))
        #expect(model.listedItemCount == 4)
    }

    @Test func anEmptyFeedHasNoFeaturedItem() {
        let scratch = ScratchDefaults()
        let model = FeedModel(newsItems: [], seenStore: FeedSeenStore(defaults: scratch.defaults))
        #expect(model.featuredItem == nil)
        #expect(model.sections.isEmpty)
        #expect(model.listedItemCount == 0)
    }

    // MARK: - Filtres

    @Test func selectingAGameRestrictsTheFeed() {
        let scratch = ScratchDefaults()
        let items = [
            sampleItem(id: "a", publishedAt: "2026-08-09", game: .leonida),
            sampleItem(id: "b", publishedAt: "2026-08-08", game: .reference),
            sampleItem(id: "c", publishedAt: "2026-08-07", game: .reference)
        ]
        let model = FeedModel(
            newsItems: items,
            seenStore: FeedSeenStore(defaults: scratch.defaults),
            now: { items[0].publishedDate! }
        )

        model.selectGame(.reference)
        #expect(model.featuredItem?.id == "b")
        #expect(model.sections.flatMap(\.items).map(\.id) == ["c"])

        model.selectGame(nil)
        #expect(model.featuredItem?.id == "a")
        #expect(model.listedItemCount == 2)
    }

    /// Le cas qui ferait afficher un fil vide sous une puce allumée.
    @Test func changingGameReleasesACategoryThatNoLongerExists() {
        let scratch = ScratchDefaults()
        let items = [
            sampleItem(id: "a", publishedAt: "2026-08-09", game: .leonida, category: .patch),
            sampleItem(id: "b", publishedAt: "2026-08-08", game: .reference, category: .business)
        ]
        let model = FeedModel(
            newsItems: items,
            seenStore: FeedSeenStore(defaults: scratch.defaults),
            now: { items[0].publishedDate! }
        )

        model.selectCategory(.patch)
        #expect(model.filter.category == .patch)

        model.selectGame(.reference)
        // « Patch » n'existe pas pour ce jeu : la rubrique est relâchée plutôt
        // que de rendre zéro carte.
        #expect(model.filter.category == nil)
        #expect(model.featuredItem?.id == "b")
    }

    @Test func aPublicationThatRemovesTheLastItemOfACategoryReleasesTheFilter() {
        let scratch = ScratchDefaults()
        let model = FeedModel(
            newsItems: [
                sampleItem(id: "a", publishedAt: "2026-08-09", category: .patch),
                sampleItem(id: "b", publishedAt: "2026-08-08", category: .business)
            ],
            seenStore: FeedSeenStore(defaults: scratch.defaults)
        )
        model.selectCategory(.patch)

        model.updateNewsItems([sampleItem(id: "b", publishedAt: "2026-08-08", category: .business)])
        #expect(model.filter.category == nil)
        #expect(model.featuredItem?.id == "b")
    }

    // MARK: - Repère de nouveauté

    @Test func nothingIsNewOnTheVeryFirstLaunch() {
        let scratch = ScratchDefaults()
        let store = FeedSeenStore(defaults: scratch.defaults)
        let model = FeedModel(newsItems: [], seenStore: store)

        // Le pire départ possible, qu'on écarte : la première synchronisation
        // marquerait tout le fil comme neuf au moment précis où l'on découvre
        // le repère.
        model.updateNewsItems((1...46).map { sampleItem(id: "\($0)", publishedAt: "2026-08-01") })
        #expect(model.newItemIDs.isEmpty)
    }

    @Test func itemsUnknownToThePreviousSessionAreNew() {
        let scratch = ScratchDefaults()
        let known = [sampleItem(id: "a", publishedAt: "2026-08-01")]

        // Première session : tout est absorbé.
        _ = FeedModel(newsItems: known, seenStore: FeedSeenStore(defaults: scratch.defaults))

        // Seconde session, deux entrées de plus.
        let second = FeedModel(
            newsItems: known + [
                sampleItem(id: "b", publishedAt: "2026-08-02"),
                sampleItem(id: "c", publishedAt: "2026-08-03")
            ],
            seenStore: FeedSeenStore(defaults: scratch.defaults)
        )
        #expect(second.newItemIDs == ["b", "c"])
    }

    @Test func itemsArrivingMidSessionStayFlaggedAlongsideTheOthers() {
        let scratch = ScratchDefaults()
        _ = FeedModel(newsItems: [sampleItem(id: "a", publishedAt: "2026-08-01")], seenStore: FeedSeenStore(defaults: scratch.defaults))

        let model = FeedModel(
            newsItems: [
                sampleItem(id: "a", publishedAt: "2026-08-01"),
                sampleItem(id: "b", publishedAt: "2026-08-02")
            ],
            seenStore: FeedSeenStore(defaults: scratch.defaults)
        )
        #expect(model.newItemIDs == ["b"])

        // Tirer-pour-rafraîchir en cours de session : la nouvelle entrée
        // s'ajoute au repère au lieu de le remplacer, sinon « b » perdrait son
        // point sans avoir été lu.
        model.updateNewsItems([
            sampleItem(id: "a", publishedAt: "2026-08-01"),
            sampleItem(id: "b", publishedAt: "2026-08-02"),
            sampleItem(id: "c", publishedAt: "2026-08-03")
        ])
        #expect(model.newItemIDs == ["b", "c"])
    }

    /// Poser un filtre ne doit pas consommer le repère des entrées qu'il masque.
    @Test func filteringDoesNotConsumeTheNewFlagOfHiddenItems() {
        let scratch = ScratchDefaults()
        _ = FeedModel(newsItems: [], seenStore: FeedSeenStore(defaults: scratch.defaults))

        let items = [
            sampleItem(id: "vi", publishedAt: "2026-08-02", game: .leonida),
            sampleItem(id: "v", publishedAt: "2026-08-01", game: .reference)
        ]
        let model = FeedModel(newsItems: items, seenStore: FeedSeenStore(defaults: scratch.defaults))
        #expect(model.newItemIDs == ["vi", "v"])

        model.selectGame(.leonida)
        // « v » est masqué, pas lu.
        #expect(model.newItemIDs == ["vi", "v"])
    }

    // MARK: - Encarts publicitaires

    /// Générateur déterministe : le tirage des encarts est aléatoire, ses
    /// invariants ne le sont pas.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    @Test func adGapsAlwaysStayWithinTheAllowedRange() {
        // Sur cent tirages et des fils de toutes tailles, aucun écart ne doit
        // sortir de 2...5 : un écart de 1 ferait alterner publicité et contenu,
        // un écart trop grand priverait un fil court de tout encart.
        for seed in 1...100 {
            var generator = SeededGenerator(state: UInt64(seed))
            for itemCount in 0...30 {
                let positions = InlineAdPlacement
                    .positions(itemCount: itemCount, using: &generator)
                    .sorted()
                var previous = -1
                for position in positions {
                    let gap = position - previous
                    #expect(InlineAdPlacement.gapRange.contains(gap), "écart \(gap) hors bornes (graine \(seed), \(itemCount) entrées)")
                    previous = position
                }
            }
        }
    }

    @Test func neverPlacesAnAdAfterTheLastCard() {
        // Terminer une liste par une publicité est le réflexe qu'on ne veut
        // pas : la garantie doit tenir pour toute taille de fil, pas seulement
        // pour celles qu'on a regardées.
        for seed in 1...100 {
            var generator = SeededGenerator(state: UInt64(seed))
            for itemCount in 0...30 {
                let positions = InlineAdPlacement.positions(itemCount: itemCount, using: &generator)
                for position in positions {
                    #expect(position < itemCount - 1, "encart après la dernière carte (graine \(seed), \(itemCount) entrées)")
                }
            }
        }
    }

    @Test func aFeedTooShortToSeparateAdsGetsNone() {
        // Deux cartes : le premier écart possible étant 2, l'encart tomberait
        // après la dernière. Il ne doit donc pas y en avoir.
        for seed in 1...50 {
            var generator = SeededGenerator(state: UInt64(seed))
            #expect(InlineAdPlacement.positions(itemCount: 2, using: &generator).isEmpty)
        }
    }

    @Test func adPositionsAreStableUntilTheContentChanges() {
        // Le piège que ce tirage évite : recalculé à chaque rendu, il ferait
        // sauter les encarts d'une position à l'autre au moindre défilement.
        let scratch = ScratchDefaults()
        let model = FeedModel(
            newsItems: (1...12).map { sampleItem(id: "\($0)", publishedAt: "2026-07-\(String(format: "%02d", $0))") },
            seenStore: FeedSeenStore(defaults: scratch.defaults)
        )
        let first = model.adPositions

        #expect(model.adPositions == first)
        #expect(model.adPositions == first)
    }

    /// Les encarts portent sur les cartes listées, pas sur le fil entier.
    @Test func adsAreNeverPlacedPastTheLastListedCard() {
        let scratch = ScratchDefaults()
        let items = (1...12).map { sampleItem(id: "\($0)", publishedAt: "2026-07-\(String(format: "%02d", $0))") }
        let model = FeedModel(
            newsItems: items,
            seenStore: FeedSeenStore(defaults: scratch.defaults),
            now: { items[11].publishedDate! }
        )
        // La une sort de la liste : un encart posé au-delà tomberait dans le vide.
        for position in model.adPositions {
            #expect(position < model.listedItemCount)
        }
    }
}
