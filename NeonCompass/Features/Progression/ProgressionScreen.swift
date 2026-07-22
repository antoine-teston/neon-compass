import SwiftUI
import SwiftData

struct ProgressionScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: ProgressionModel?

    var body: some View {
        Group {
            if let model {
                ProgressionListView(model: model)
            } else {
                ProgressView()
                    .task { await loadModel() }
            }
        }
    }

    private func loadModel() async {
        guard model == nil else { return }
        let poiStore = ContentStore<POI>(
            collectionName: "poi",
            remote: FirestoreContentRepository<POI>(collectionName: "poi"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        let trophyStore = ContentStore<Trophy>(
            collectionName: "trophies",
            remote: FirestoreContentRepository<Trophy>(collectionName: "trophies"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = ProgressionModel(pois: poiStore.items, trophies: trophyStore.items, modelContext: modelContext)
        try? await poiStore.syncIfNeeded()
        try? await trophyStore.syncIfNeeded()
        model?.updatePOIs(poiStore.items)
        model?.updateTrophies(trophyStore.items)
    }
}
