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
                    .task { await loadModel() }
            }
        }
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
