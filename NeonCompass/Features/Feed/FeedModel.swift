import Foundation
import Observation

@Observable
@MainActor
final class FeedModel {
    private(set) var newsItems: [NewsItem]

    /// Retenu pour que le fil puisse être rafraîchi à la demande. Optionnel :
    /// les tests construisent le modèle à partir d'entrées nues, sans store ni
    /// SwiftData.
    private let contentStore: ContentStore<NewsItem>?

    init(newsItems: [NewsItem], contentStore: ContentStore<NewsItem>? = nil) {
        self.newsItems = Self.sortedByMostRecent(newsItems)
        self.contentStore = contentStore
        var generator = SystemRandomNumberGenerator()
        self.adPositions = InlineAdPlacement.positions(itemCount: self.newsItems.count, using: &generator)
    }

    /// Index des cartes après lesquelles un encart publicitaire s'intercale.
    ///
    /// Tiré ICI et pas dans la vue, et c'est tout l'enjeu : un tirage refait à
    /// chaque évaluation du corps de la vue déplacerait les encarts au moindre
    /// rendu — un défilement, une rotation, un changement d'abonnement — et le
    /// fil sauterait sous le doigt. Le tirage ne change qu'avec le contenu.
    private(set) var adPositions: Set<Int> = []

    func updateNewsItems(_ newItems: [NewsItem]) {
        newsItems = Self.sortedByMostRecent(newItems)
        var generator = SystemRandomNumberGenerator()
        adPositions = InlineAdPlacement.positions(itemCount: newsItems.count, using: &generator)
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

    private static func sortedByMostRecent(_ items: [NewsItem]) -> [NewsItem] {
        items.sorted { $0.publishedAt > $1.publishedAt }
    }
}
