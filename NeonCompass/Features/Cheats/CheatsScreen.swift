import SwiftUI
import SwiftData

struct CheatsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSummaryCoordinator.self) private var widgetSummaryCoordinator
    @State private var model: CheatsModel?
    @State private var readerCheat: Cheat?

    // Guides is temporarily removed from this screen pending a redesign of
    // how users switch between Cheats and Guides (the previous segmented
    // Picker wasn't the right UX) — GuidesModel/GuidesListView/
    // GuideDetailView/Guide.swift are untouched and ready to be reattached
    // once that design exists.

    var body: some View {
        Group {
            if let model {
                cheatsContent(model: model)
            } else {
                ProgressView().task { await loadCheatsModel() }
            }
        }
    }

    private func cheatsContent(model: CheatsModel) -> some View {
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
    }

    private func loadCheatsModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<Cheat>.live(
            collectionName: "cheats",
            modelContext: modelContext
        )
        model = CheatsModel(
            cheats: contentStore.items,
            modelContext: modelContext,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )
        try? await contentStore.syncIfNeeded()
        model?.updateCheats(contentStore.items)
    }
}
