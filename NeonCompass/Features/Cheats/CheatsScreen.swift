import SwiftUI
import SwiftData

struct CheatsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: CheatsModel?
    @State private var readerCheat: Cheat?

    var body: some View {
        Group {
            if let model {
                CheatsListView(model: model) { cheat in
                    readerCheat = cheat
                }
                .fullScreenCover(item: $readerCheat) { cheat in
                    if let index = model.filteredCheats.firstIndex(where: { $0.id == cheat.id }) {
                        CheatReaderView(
                            cheats: model.filteredCheats,
                            startIndex: index,
                            platform: model.activePlatform,
                            onDismiss: { readerCheat = nil }
                        )
                    }
                }
            } else {
                ProgressView()
                    .task { await loadModel() }
            }
        }
    }

    private func loadModel() async {
        guard model == nil else { return }
        let contentStore = CheatContentStore(
            remote: FirestoreCheatRepository(),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = CheatsModel(cheats: contentStore.cheats, modelContext: modelContext)
        try? await contentStore.syncIfNeeded()
        model?.updateCheats(contentStore.cheats)
    }
}
