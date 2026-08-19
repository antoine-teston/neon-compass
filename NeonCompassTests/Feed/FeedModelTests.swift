import Testing
import Foundation
@testable import NeonCompass

@MainActor
struct FeedModelTests {
    private func sampleItem(
        id: String,
        publishedAt: String,
        listedAt: String? = nil,
        game: Game = .leonida,
        category: NewsCategory = .announcement
    ) -> NewsItem {
        NewsItem(
            id: id,
            category: category,
            title: LocalizedText(en: "Title \(id)", fr: nil, es: nil, it: nil, de: nil),
            body: LocalizedText(en: "Body \(id)", fr: nil, es: nil, it: nil, de: nil),
            publishedAt: publishedAt,
            listedAt: listedAt,
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

    /// LE CAS QUI A FAIT TOMBER `listedAt`, le 2026-08-19.
    ///
    /// Le fil AFFICHE `publishedAt` sur chaque carte. Tant qu'il s'ordonnait sur
    /// `listedAt`, une entrée mise en ligne aujourd'hui pour une information
    /// d'il y a un mois passait devant une information de la semaine — et le
    /// lecteur voyait les dates remonter en descendant la liste.
    ///
    /// Une liste s'ordonne sur la date qu'elle montre, sinon elle se lit comme
    /// cassée. `listedAt` continue d'être décodé, il n'ordonne plus rien.
    @Test func ordersOnTheInformationDateEvenWhenListedLater() {
        let scratch = ScratchDefaults()
        let vieilleInfoMiseEnLigneAujourdhui = sampleItem(id: "retard", publishedAt: "2026-07-19", listedAt: "2026-08-19")
        let infoDeLaSemaine = sampleItem(id: "fraiche", publishedAt: "2026-08-14", listedAt: "2026-08-14")
        let model = FeedModel(
            newsItems: [vieilleInfoMiseEnLigneAujourdhui, infoDeLaSemaine],
            seenStore: FeedSeenStore(defaults: scratch.defaults)
        )
        #expect(model.newsItems.map(\.id) == ["fraiche", "retard"])
    }

    /// La mise en ligne ne rattrape JAMAIS l'information, dans aucun sens : ni
    /// pour faire monter une vieille actu, ni pour en faire descendre une neuve.
    /// C'est le même invariant que le test précédent, pris par l'autre bout —
    /// un tri qui lirait encore `listedAt` en second passerait l'un et pas
    /// l'autre.
    @Test func theListingDayNeverOutranksTheInformationDate() {
        let scratch = ScratchDefaults()
        let items = [
            sampleItem(id: "info-neuve-listee-jadis", publishedAt: "2026-08-18", listedAt: "2026-06-09"),
            sampleItem(id: "info-vieille-listee-ce-matin", publishedAt: "2026-07-19", listedAt: "2026-08-19")
        ]
        let model = FeedModel(newsItems: items, seenStore: FeedSeenStore(defaults: scratch.defaults))
        #expect(model.newsItems.map(\.id) == ["info-neuve-listee-jadis", "info-vieille-listee-ce-matin"])
    }

    /// Une entrée sans `listedAt` s'ordonne exactement comme une entrée qui en
    /// porte un : le champ ne participe plus, donc son absence ne change rien.
    @Test func fallsBackToThePublicationDateWhenNothingWasStamped() {
        let scratch = ScratchDefaults()
        let items = [
            sampleItem(id: "a", publishedAt: "2026-07-01"),
            sampleItem(id: "b", publishedAt: "2026-07-20")
        ]
        let model = FeedModel(newsItems: items, seenStore: FeedSeenStore(defaults: scratch.defaults))
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }

    /// Un fil mixte — des entrées estampillées et des entrées qui ne le sont pas
    /// — s'ordonne sur la seule date de l'information, sans que l'estampille
    /// crée deux régimes.
    @Test func mixesStampedAndUnstampedItemsInOneOrder() {
        let scratch = ScratchDefaults()
        let items = [
            sampleItem(id: "ancienne", publishedAt: "2026-08-05"),
            sampleItem(id: "neuve", publishedAt: "2026-08-02", listedAt: "2026-08-17"),
            sampleItem(id: "vieille", publishedAt: "2026-07-30")
        ]
        let model = FeedModel(newsItems: items, seenStore: FeedSeenStore(defaults: scratch.defaults))
        #expect(model.newsItems.map(\.id) == ["ancienne", "neuve", "vieille"])
    }

    /// `sorted(by:)` de Swift N'EST PAS STABLE, et le fil publie régulièrement
    /// plusieurs actus datées du même jour — trois cartes du 3 août coexistaient
    /// au 2026-08-19. Sans un dernier critère total, leur ordre relatif change
    /// d'un tri à l'autre : le fil se réordonne tout seul sous le doigt après un
    /// tirer-pour-rafraîchir, sans qu'aucun contenu ait bougé.
    ///
    /// L'identifiant tranche. Sa valeur n'a aucun sens éditorial, et c'est
    /// justement ce qu'on lui demande : être arbitraire mais TOUJOURS le même.
    @Test func breaksTiesOnTheIdentifierSoTheOrderNeverWobbles() {
        let scratch = ScratchDefaults()
        let jourIdentique = ["c", "a", "b"].map { sampleItem(id: $0, publishedAt: "2026-08-03") }
        let model = FeedModel(newsItems: jourIdentique, seenStore: FeedSeenStore(defaults: scratch.defaults))
        #expect(model.newsItems.map(\.id) == ["c", "b", "a"])

        // Le même lot dans un autre ordre d'arrivée doit rendre le même fil.
        let autreOrdre = FeedModel(
            newsItems: ["b", "c", "a"].map { sampleItem(id: $0, publishedAt: "2026-08-03") },
            seenStore: FeedSeenStore(defaults: ScratchDefaults().defaults)
        )
        #expect(autreOrdre.newsItems.map(\.id) == ["c", "b", "a"])
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

    /// Revenir au même filtre doit redonner le MÊME placement.
    ///
    /// Non-régression d'un défaut mesuré : le fil retirait au hasard à chaque
    /// changement de filtre, donc les encarts se déplaçaient à chaque tap de
    /// puce — y compris en revenant à l'état précédent, où rien n'avait bougé.
    /// Chaque déplacement détruisait et recréait une `BannerAdView`, donc une
    /// requête AdMob dans le chemin du tap.
    ///
    /// Le commentaire d'`InlineAdPlacement.positions(itemCount:)` prévoyait
    /// exactement ce cas — « pour une liste qui se refiltre en continu » — mais
    /// le fil ne se refiltrait pas encore quand il a été écrit.
    @Test func returningToTheSameFilterRestoresTheSameAdPositions() {
        let scratch = ScratchDefaults()
        let items = (1...30).map {
            sampleItem(
                id: "\($0)",
                publishedAt: "2026-07-\(String(format: "%02d", ($0 % 28) + 1))",
                category: $0.isMultiple(of: 2) ? .patch : .business
            )
        }
        let model = FeedModel(newsItems: items, seenStore: FeedSeenStore(defaults: scratch.defaults))

        var restricted: [Set<Int>] = []
        var unrestricted: [Set<Int>] = []
        for _ in 0..<6 {
            model.selectCategory(.patch)
            restricted.append(model.adPositions)
            model.selectCategory(nil)
            unrestricted.append(model.adPositions)
        }

        #expect(Set(restricted).count == 1, "les encarts sautent alors que le filtre est le même")
        #expect(Set(unrestricted).count == 1, "les encarts sautent alors que le filtre est le même")
        // Deux filtres DIFFÉRENTS ont le droit de placer différemment : ce n'est
        // plus la même liste, et le tirage suit le nombre de cartes.
        #expect(restricted[0] != unrestricted[0])
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
