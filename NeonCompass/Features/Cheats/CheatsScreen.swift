import SwiftUI
import SwiftData

struct CheatsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSummaryCoordinator.self) private var widgetSummaryCoordinator
    @State private var model: CheatsModel?
    @State private var readerCheat: Cheat?

    // Guides reste hors de cet écran en attendant une refonte de la bascule
    // Codes/Guides (le Picker segmenté n'était pas la bonne UX pour arbitrer
    // deux types de contenu). GuidesModel/GuidesListView/GuideDetailView/
    // Guide.swift sont intacts et prêts à être rebranchés.
    //
    // Le segmenté qui revient dans la liste porte sur autre chose : le mode de
    // saisie est une loupe sur une même liste, pas une navigation entre deux
    // contenus.

    var body: some View {
        Group {
            if let model {
                cheatsContent(model: model)
            } else {
                ProgressView()
            }
        }
        // Cf. FeedScreen : accrochée au ProgressView, cette tâche s'annulait
        // elle-même dès que `model` était assigné, et `updateCheats` n'était
        // jamais atteint.
        .task { await loadCheatsModel() }
    }

    @ViewBuilder
    private func cheatsContent(model: CheatsModel) -> some View {
        Group {
            if model.isAwaitingContent {
                // La bascule vit dans la barre de recherche de la liste, qui n'est
                // pas là dans cet état : sans elle ici, on partirait sur GTA VI
                // sans pouvoir revenir.
                CheatsEmptyGameView(game: Binding(
                    get: { model.activeGame },
                    set: { model.activeGame = $0 }
                ))
            } else {
                CheatsListView(model: model) { cheat in
                    readerCheat = cheat
                }
            }
        }
        .fullScreenCover(item: $readerCheat) { cheat in
            let readable = model.sections.flatMap(\.cheats)
            if let index = readable.firstIndex(where: { $0.id == cheat.id }) {
                CheatReaderView(
                    cheats: readable,
                    startIndex: index,
                    inputMode: model.activeInputMode,
                    onDismiss: { readerCheat = nil }
                )
            }
        }
    }

    // La bascule de jeu n'est pas dans une toolbar : cet écran n'a pas de barre
    // de navigation. `RootView` empile ses écrans dans un `ZStack` avec une barre
    // d'onglets maison en compact, et un `TabView` en régulier — un
    // `ToolbarItem(placement: .topBarTrailing)` n'y a nulle part où se rendre, et
    // disparaissait sans la moindre erreur. Elle partage donc la ligne de
    // recherche de la liste.

    private func loadCheatsModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<Cheat>.live(
            collectionName: "cheats",
            seed: CheatLoader.bundled,
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
