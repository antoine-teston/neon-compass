import SwiftUI
import SwiftData

struct ProgressionScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
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
        .onAppear {
            model?.refreshFoundState()
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
        // Cloud progression sync is Pro + signed-in only (spec: "nécessite
        // le compte") — never constructed for free or signed-out users.
        let userID = authModel.userID
        let sync: ProgressionSyncing? = (proEntitlementModel.isProEntitled && userID != nil) ? FirestoreProgressionSync() : nil
        model = ProgressionModel(pois: poiStore.items, trophies: trophyStore.items, modelContext: modelContext, sync: sync)
        try? await poiStore.syncIfNeeded()
        try? await trophyStore.syncIfNeeded()
        model?.updatePOIs(poiStore.items)
        model?.updateTrophies(trophyStore.items)
        if let sync, let userID {
            let remoteItems = await sync.fetchAll(uid: userID)
            model?.reconcile(with: remoteItems)
        }
    }
}
