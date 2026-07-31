import Testing
@testable import NeonCompass

@MainActor
struct FeedModelTests {
    private func sampleItem(id: String, publishedAt: String) -> NewsItem {
        NewsItem(
            id: id,
            category: .announcement,
            title: LocalizedText(en: "Title \(id)", fr: nil, es: nil, it: nil, de: nil),
            body: LocalizedText(en: "Body \(id)", fr: nil, es: nil, it: nil, de: nil),
            publishedAt: publishedAt
        )
    }

    @Test func sortsNewsItemsByMostRecentFirst() {
        let older = sampleItem(id: "a", publishedAt: "2026-07-01")
        let newer = sampleItem(id: "b", publishedAt: "2026-07-20")
        let model = FeedModel(newsItems: [older, newer])
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }

    @Test func updateNewsItemsReplacesContentAndResorts() {
        let model = FeedModel(newsItems: [])
        let older = sampleItem(id: "a", publishedAt: "2026-07-01")
        let newer = sampleItem(id: "b", publishedAt: "2026-07-20")
        model.updateNewsItems([older, newer])
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }

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
                let positions = FeedModel
                    .drawAdPositions(itemCount: itemCount, using: &generator)
                    .sorted()
                var previous = -1
                for position in positions {
                    let gap = position - previous
                    #expect(FeedModel.adGapRange.contains(gap), "écart \(gap) hors bornes (graine \(seed), \(itemCount) entrées)")
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
                let positions = FeedModel.drawAdPositions(itemCount: itemCount, using: &generator)
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
            #expect(FeedModel.drawAdPositions(itemCount: 2, using: &generator).isEmpty)
        }
    }

    @Test func adPositionsAreStableUntilTheContentChanges() {
        // Le piège que ce tirage évite : recalculé à chaque rendu, il ferait
        // sauter les encarts d'une position à l'autre au moindre défilement.
        let model = FeedModel(newsItems: (1...12).map { sampleItem(id: "\($0)", publishedAt: "2026-07-\(String(format: "%02d", $0))") })
        let first = model.adPositions

        #expect(model.adPositions == first)
        #expect(model.adPositions == first)
    }
}
