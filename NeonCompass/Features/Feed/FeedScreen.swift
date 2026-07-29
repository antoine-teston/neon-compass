import SwiftUI
import SwiftData

struct FeedScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: FeedModel?

    var body: some View {
        Group {
            if let model {
                FeedListView(model: model)
            } else {
                ProgressView()
            }
        }
        // La tâche appartient à l'ÉCRAN, jamais au ProgressView.
        //
        // Accrochée au ProgressView, elle s'annulait elle-même : `loadModel()`
        // commence par assigner `model`, ce qui bascule le `if let`, retire le
        // ProgressView de l'arbre, et SwiftUI annule la tâche qui lui
        // appartenait. L'`await` suivant reprenait dans un contexte annulé, le
        // `try?` avalait l'annulation, et `updateNewsItems` n'était jamais
        // atteint. Le fil restait vide en permanence — sans erreur, sans trace,
        // quel que soit le contenu publié.
        .task { await loadModel() }
    }

    private func loadModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<NewsItem>.live(
            collectionName: "news",
            modelContext: modelContext
        )
        model = FeedModel(newsItems: contentStore.items)
        try? await contentStore.syncIfNeeded()
        model?.updateNewsItems(contentStore.items)
    }
}
