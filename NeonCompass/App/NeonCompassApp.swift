import SwiftData
import SwiftUI

@main
struct NeonCompassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Le conteneur est construit ICI plutôt que par `.modelContainer(for:)`.
    ///
    /// La raison est `FoundStore` : il doit exister avant le premier rendu, parce
    /// que la carte et le profil le reçoivent par l'environnement, et il lui faut
    /// un `ModelContext`. Le modificateur, lui, ne rend le contexte disponible
    /// qu'À L'INTÉRIEUR de la vue — trop tard pour le fournir à cette même vue
    /// sans passer par un état facultatif et une image de chargement à chaque
    /// lancement. Le conteneur explicite rétablit l'ordre : conteneur, puis
    /// magasin, puis vues.
    ///
    /// `try!` assumé, et c'est exactement ce que fait `.modelContainer(for:)` :
    /// un schéma qu'on n'arrive pas à ouvrir est une app qui n'a rien à afficher.
    private let modelContainer: ModelContainer
    @State private var foundStore: FoundStore

    init() {
        let container = try! ModelContainer(
            for: FoundEntry.self, PersonalPin.self, FavoriteCheat.self,
            ContentCacheEntry.self, TrophyProgress.self, BlockedContributor.self
        )
        modelContainer = container
        _foundStore = State(initialValue: FoundStore(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(foundStore)
        }
        .modelContainer(modelContainer)
    }
}
