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
            if isAwaitingContent(model) {
                CheatsEmptyGameView()
            } else {
                CheatsListView(model: model) { cheat in
                    readerCheat = cheat
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                gamePicker(model: model)
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

    /// Un jeu dont aucun code n'existe encore — pas une recherche sans résultat.
    /// La condition inclut donc `searchQuery.isEmpty` : afficher « pas encore de
    /// codes » parce qu'une recherche ne trouve rien serait un mensonge.
    private func isAwaitingContent(_ model: CheatsModel) -> Bool {
        model.sections.isEmpty
            && model.unavailableInActiveMode.isEmpty
            && model.searchQuery.isEmpty
    }

    /// Le jeu est un changement de contexte — tout le contenu change — donc il
    /// vit dans le chrome, pas dans la liste. Deux segments, l'étiquette courte
    /// que le fil d'actu utilise déjà.
    private func gamePicker(model: CheatsModel) -> some View {
        Picker("cheats.game.picker", selection: Binding(
            get: { model.activeGame },
            set: { model.activeGame = $0 }
        )) {
            // Ordre explicite, pas `allCases` : l'énumération déclare `leonida`
            // en premier et le sélecteur afficherait « VI | V ».
            ForEach([Game.reference, .leonida]) { game in
                Text(game.shortLabel).tag(game)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
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
