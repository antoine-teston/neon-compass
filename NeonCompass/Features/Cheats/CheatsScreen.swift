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
        VStack(spacing: 0) {
            gameRow(model: model)
            if model.isAwaitingContent {
                CheatsEmptyGameView()
            } else {
                CheatsListView(model: model) { cheat in
                    readerCheat = cheat
                }
            }
        }
        .background(NCColor.nightSky.ignoresSafeArea())
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

    /// Le jeu est un changement de contexte — tout le contenu change — donc il
    /// se distingue du mode de saisie, qui n'est qu'une loupe sur une même liste.
    ///
    /// Hors du défilement, et au-dessus des deux états : sur l'état d'attente de
    /// GTA VI, une bascule qui aurait vécu dans la liste aurait disparu avec
    /// elle, et on serait parti sur VI sans pouvoir revenir.
    ///
    /// Pas dans une toolbar : cet écran n'a pas de barre de navigation. `RootView`
    /// empile ses écrans dans un `ZStack` avec une barre d'onglets maison en
    /// compact, et un `TabView` en régulier — un
    /// `ToolbarItem(placement: .topBarTrailing)` n'y a nulle part où se rendre, et
    /// disparaissait sans la moindre erreur.
    private func gameRow(model: CheatsModel) -> some View {
        HStack {
            Spacer()
            GameSwitch(game: Binding(
                get: { model.activeGame },
                set: { model.activeGame = $0 }
            ))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

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
