import SwiftUI
import SwiftData

private enum CheatsGuidesSection: String, CaseIterable {
    case cheats, guides
}

struct CheatsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: CheatsModel?
    @State private var guidesModel: GuidesModel?
    @State private var readerCheat: Cheat?
    @State private var selectedGuide: Guide?
    @State private var section: CheatsGuidesSection = .cheats

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            Group {
                switch section {
                case .cheats:
                    if let model {
                        cheatsContent(model: model)
                    } else {
                        ProgressView().task { await loadCheatsModel() }
                    }
                case .guides:
                    if let guidesModel {
                        GuidesListView(model: guidesModel) { guide in
                            selectedGuide = guide
                        }
                        .sheet(item: $selectedGuide) { guide in
                            GuideDetailView(guide: guide)
                        }
                    } else {
                        ProgressView().task { await loadGuidesModel() }
                    }
                }
            }
        }
    }

    private var sectionPicker: some View {
        Picker("cheatsGuides.section.picker", selection: $section) {
            Text("cheatsGuides.section.cheats").tag(CheatsGuidesSection.cheats)
            Text("cheatsGuides.section.guides").tag(CheatsGuidesSection.guides)
        }
        .pickerStyle(.segmented)
        .padding(16)
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
        let contentStore = ContentStore<Cheat>(
            collectionName: "cheats",
            remote: FirestoreContentRepository<Cheat>(collectionName: "cheats"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = CheatsModel(cheats: contentStore.items, modelContext: modelContext)
        try? await contentStore.syncIfNeeded()
        model?.updateCheats(contentStore.items)
    }

    private func loadGuidesModel() async {
        guard guidesModel == nil else { return }
        let contentStore = GuideContentStore(
            remote: FirestoreGuideRepository(),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        guidesModel = GuidesModel(guides: contentStore.guides)
        try? await contentStore.syncIfNeeded()
        guidesModel?.updateGuides(contentStore.guides)
    }
}
