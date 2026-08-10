import SwiftUI
import SwiftData

struct CheatsScreen: View {
    /// Le jeu vient de `AppModel`, parce que la bascule vit dans la barre haute
    /// que `RootView` monte au-dessus de cet écran. L'écran le reçoit et le pousse
    /// dans son modèle ; il ne le détient pas.
    let game: Game

    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSummaryCoordinator.self) private var widgetSummaryCoordinator
    @Environment(InterstitialCoordinator.self) private var interstitialCoordinator
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
        // Le modèle naît avec le bon jeu ; cette liaison ne sert qu'aux
        // changements ultérieurs. Elle porte le `didSet` du modèle, qui relâche
        // une rubrique que le nouveau jeu ne propose pas et recalcule.
        .onChange(of: game) { _, newGame in model?.activeGame = newGame }
    }

    @ViewBuilder
    private func cheatsContent(model: CheatsModel) -> some View {
        Group {
            if model.isAwaitingContent {
                // Plus de bascule de secours ici : elle vivait en tête de la
                // liste, absente dans cet état, et il fallait donc la redonner
                // pour ne pas enfermer sur le jeu à venir. La barre haute la
                // porte maintenant, et la barre est là quoi qu'affiche l'écran.
                CheatsEmptyGameView()
            } else {
                CheatsListView(model: model) { cheat in
                    readerCheat = cheat
                }
            }
        }
        // Le lecteur refermé, l'utilisateur a obtenu le code qu'il venait
        // chercher : c'est la pause naturelle. La carte, elle, ne reçoit RIEN —
        // c'est là que le geste s'enchaîne, et une pleine page au milieu d'une
        // exploration est l'interruption la plus coûteuse que l'app puisse
        // produire.
        .fullScreenCover(item: $readerCheat, onDismiss: {
            Task { await interstitialCoordinator.contentConsumed() }
        }) { cheat in
            // `readableCheats` et non `sections` : les favoris n'y sont plus, et
            // taper l'un d'eux présentait une pleine page vide.
            let readable = model.readableCheats
            let index = readable.firstIndex { $0.id == cheat.id }
            // Le repli n'est pas décoratif. Une feuille plein écran dont le
            // contenu ne se construit pas est un cul-de-sac : elle s'affiche
            // vide, et son bouton de fermeture n'existe pas non plus. Plutôt
            // qu'un `if let` qui laisse ce cas ouvert, on lit la triche seule.
            CheatReaderView(
                cheats: index == nil ? [cheat] : readable,
                startIndex: index ?? 0,
                inputMode: model.activeInputMode,
                onDismiss: { readerCheat = nil }
            )
        }
    }

    // La bascule de jeu n'est pas dans une toolbar : cet écran n'a pas de barre
    // de navigation. `RootView` empile ses écrans dans un `ZStack` avec une barre
    // d'onglets maison en compact, et un `TabView` en régulier — un
    // `ToolbarItem(placement: .topBarTrailing)` n'y a nulle part où se rendre, et
    // disparaissait sans la moindre erreur. Elle ouvre donc la liste, centrée en
    // tête, où elle tient lieu du titre que cet écran n'a pas.

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
