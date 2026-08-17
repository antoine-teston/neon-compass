import Testing
import Foundation
@testable import NeonCompass

struct FeedFilteringTests {
    private func item(
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

    /// Passe par la MÊME conversion que le code testé plutôt que par un
    /// formateur monté pour l'occasion : deux formateurs aux fuseaux différents
    /// feraient tomber le groupement d'un jour selon la machine.
    private func date(_ isoDate: String) -> Date {
        item(id: "ref", publishedAt: isoDate).publishedDate!
    }

    // MARK: - Filtrage

    @Test func filtersByGame() {
        let items = [
            item(id: "a", publishedAt: "2026-08-09", game: .leonida),
            item(id: "b", publishedAt: "2026-08-08", game: .reference)
        ]
        #expect(FeedFiltering.apply(FeedFilter(game: .reference, category: nil), to: items).map(\.id) == ["b"])
        #expect(FeedFiltering.apply(.all, to: items).count == 2)
    }

    @Test func filtersByGameAndCategoryTogether() {
        let items = [
            item(id: "a", publishedAt: "2026-08-09", game: .leonida, category: .patch),
            item(id: "b", publishedAt: "2026-08-08", game: .leonida, category: .business),
            item(id: "c", publishedAt: "2026-08-07", game: .reference, category: .patch)
        ]
        let filtered = FeedFiltering.apply(FeedFilter(game: .leonida, category: .patch), to: items)
        #expect(filtered.map(\.id) == ["a"])
    }

    // MARK: - Choix proposés

    @Test func onlyOffersCategoriesThatWouldReturnSomething() {
        let items = [
            item(id: "a", publishedAt: "2026-08-09", game: .leonida, category: .patch),
            item(id: "b", publishedAt: "2026-08-08", game: .reference, category: .business)
        ]
        #expect(FeedFiltering.availableCategories(in: items, game: .leonida) == [.patch])
        #expect(FeedFiltering.availableCategories(in: items, game: .reference) == [.business])
        // Sans restriction de jeu, les deux — dans l'ordre de `allCases` et non
        // dans celui du contenu, sinon les puces changeraient de place à chaque
        // publication.
        #expect(FeedFiltering.availableCategories(in: items, game: nil) == [.patch, .business])
    }

    @Test func offersNoGameChoiceWhenTheFeedCoversOnlyOne() {
        let single = [
            item(id: "a", publishedAt: "2026-08-09", game: .leonida),
            item(id: "b", publishedAt: "2026-08-08", game: .leonida)
        ]
        // Proposer de filtrer sur une valeur unique est un choix sans effet,
        // donc du bruit sur une rangée déjà chargée.
        #expect(FeedFiltering.availableGames(in: single).isEmpty)

        let both = single + [item(id: "c", publishedAt: "2026-08-07", game: .reference)]
        #expect(FeedFiltering.availableGames(in: both) == [.leonida, .reference])
    }

    @Test func offersNoChoiceAtAllOnAnEmptyFeed() {
        #expect(FeedFiltering.availableGames(in: []).isEmpty)
        #expect(FeedFiltering.availableCategories(in: [], game: nil).isEmpty)
    }

    // MARK: - Tranches de temps

    @Test func groupsItemsIntoThreePeriods() {
        let now = date("2026-08-09")
        let items = [
            item(id: "today", publishedAt: "2026-08-09"),
            item(id: "sixDays", publishedAt: "2026-08-03"),
            item(id: "tenDays", publishedAt: "2026-07-30"),
            item(id: "twoMonths", publishedAt: "2026-06-09")
        ]
        let sections = FeedFiltering.sections(from: items, now: now)

        #expect(sections.map(\.period) == [.thisWeek, .thisMonth, .earlier])
        #expect(sections[0].items.map(\.id) == ["today", "sixDays"])
        #expect(sections[1].items.map(\.id) == ["tenDays"])
        #expect(sections[2].items.map(\.id) == ["twoMonths"])
    }

    /// Le groupement suit le TRI, donc la date de mise en ligne.
    ///
    /// Il ne peut pas en être autrement : grouper sur une date et trier sur une
    /// autre rendrait les tranches non monotones — une carte sauterait d'une
    /// section à l'autre au milieu de la liste. La conséquence assumée est
    /// qu'une carte affichée « 30 juil. » peut se ranger sous « cette semaine »
    /// si c'est cette semaine qu'elle est apparue.
    @Test func groupsOnTheDayItWentLiveRatherThanTheDayTheNewsBroke() {
        let now = date("2026-08-09")
        let items = [
            item(id: "vieilleInfoNeuveDansLeFil", publishedAt: "2026-06-09", listedAt: "2026-08-09"),
            item(id: "infoFraicheMiseEnLigneJadis", publishedAt: "2026-08-09", listedAt: "2026-06-09")
        ]
        let sections = FeedFiltering.sections(from: items, now: now)

        #expect(sections.map(\.period) == [.thisWeek, .earlier])
        #expect(sections[0].items.map(\.id) == ["vieilleInfoNeuveDansLeFil"])
        #expect(sections[1].items.map(\.id) == ["infoFraicheMiseEnLigneJadis"])
    }

    /// Sans estampille, le groupement est exactement celui d'avant le champ.
    @Test func fallsBackToThePublicationDateWhenNothingWasStamped() {
        let sections = FeedFiltering.sections(
            from: [item(id: "a", publishedAt: "2026-08-09"), item(id: "b", publishedAt: "2026-06-09")],
            now: date("2026-08-09")
        )
        #expect(sections.map(\.period) == [.thisWeek, .earlier])
    }

    @Test func omitsPeriodsThatHaveNoItems() {
        let sections = FeedFiltering.sections(
            from: [item(id: "a", publishedAt: "2026-08-09")],
            now: date("2026-08-09")
        )
        // Un en-tête sans rien dessous est pire que pas d'en-tête du tout.
        #expect(sections.map(\.period) == [.thisWeek])
    }

    @Test func periodBoundariesFallOnTheExpectedSide() {
        let now = date("2026-08-09")
        // Le septième jour bascule dans le mois, le trentième dans « plus tôt ».
        let boundary = [
            item(id: "day6", publishedAt: "2026-08-03"),
            item(id: "day7", publishedAt: "2026-08-02"),
            item(id: "day29", publishedAt: "2026-07-11"),
            item(id: "day30", publishedAt: "2026-07-10")
        ]
        let byID = Dictionary(
            uniqueKeysWithValues: FeedFiltering.sections(from: boundary, now: now)
                .flatMap { section in section.items.map { ($0.id, section.period) } }
        )
        #expect(byID["day6"] == .thisWeek)
        #expect(byID["day7"] == .thisMonth)
        #expect(byID["day29"] == .thisMonth)
        #expect(byID["day30"] == .earlier)
    }

    @Test func anUnreadableDateStillLandsSomewhere() {
        // Le fil ne doit jamais perdre une carte à cause du format d'un champ :
        // une date illisible se range en bas plutôt que de disparaître.
        let sections = FeedFiltering.sections(
            from: [item(id: "broken", publishedAt: "pas une date")],
            now: date("2026-08-09")
        )
        #expect(sections.map(\.period) == [.earlier])
        #expect(sections[0].items.map(\.id) == ["broken"])
    }

    @Test func aFutureDateCountsAsThisWeek() {
        // Le contenu est daté au jour : une entrée publiée depuis un autre
        // fuseau peut légitimement porter la date de demain.
        let sections = FeedFiltering.sections(
            from: [item(id: "tomorrow", publishedAt: "2026-08-10")],
            now: date("2026-08-09")
        )
        #expect(sections.map(\.period) == [.thisWeek])
    }

    @Test func groupingPreservesTheIncomingOrder() {
        let now = date("2026-08-09")
        let items = [
            item(id: "a", publishedAt: "2026-08-09"),
            item(id: "b", publishedAt: "2026-08-08"),
            item(id: "c", publishedAt: "2026-08-07")
        ]
        #expect(FeedFiltering.sections(from: items, now: now)[0].items.map(\.id) == ["a", "b", "c"])
    }
}
