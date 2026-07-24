import SwiftUI
import SwiftData

struct ProgressionScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSummaryCoordinator.self) private var widgetSummaryCoordinator
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
            reattachSyncIfNeeded()
        }
    }

    /// Closes the race where `loadModel()` ran once before
    /// `ProEntitlementModel.refresh()` completed at app launch, capturing
    /// `sync == nil` permanently for this screen instance (SwiftUI retains
    /// `@State` across iPad tab switches, so `loadModel()` itself never
    /// re-runs). Cheap no-op whenever the Pro/auth gate is still false.
    private func reattachSyncIfNeeded() {
        guard let model, proEntitlementModel.isProEntitled, let userID = authModel.userID else { return }
        let sync = FirestoreProgressionSync()
        guard model.attachSyncIfNeeded(sync) else { return }
        Task {
            let remoteItems = await sync.fetchAll(uid: userID)
            model.reconcile(with: remoteItems)
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
        model = ProgressionModel(
            pois: poiStore.items,
            trophies: trophyStore.items,
            modelContext: modelContext,
            sync: sync,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )
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
