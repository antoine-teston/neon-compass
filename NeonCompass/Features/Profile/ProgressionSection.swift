import SwiftUI
import SwiftData

/// Les défis et les trophées, embarqués dans le Profil.
///
/// Porte son propre chargement plutôt que de le recevoir : c'est exactement
/// celui de l'ancien `ProgressionScreen`, déplacé sans être touché. Deux
/// mécanismes subtils en dépendent — `RootView.hydrateWidgetSummaryFromCache()`
/// construit un second `ProgressionModel` au lancement pour alimenter le
/// widget, et `reattachSyncIfNeeded()` referme une course entre l'entitlement
/// Pro et la construction du modèle. Tous deux sont nés de bugs réels ; les
/// remanier en même temps qu'un déplacement d'écran mêlerait deux risques sans
/// rapport.
struct ProgressionSection: View {
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
            }
        }
        // Cf. FeedScreen : accrochée au ProgressView, cette tâche s'annulait
        // elle-même dès que `model` était assigné. Les QUATRE synchronisations
        // qui suivent ne repartaient donc jamais — l'écran vivait sur le seul
        // socle embarqué. Les trophées, qui n'en ont pas, restaient vides, et
        // l'overlay distant ne s'appliquait pas : corriger un POI publié sans
        // repasser par l'App Store, tout l'intérêt de l'overlay, ne marchait
        // pas ici.
        .task { await loadModel() }
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
        let poiStore = ContentStore<POI>.live(collectionName: "poi", modelContext: modelContext)
        // Même socle + overlay que la carte : les défis de la carte de
        // référence doivent compter les mêmes POI que ceux qu'on peut y cocher.
        let referenceStore = ContentStore<POI>.live(
            collectionName: "poi_gtav",
            seed: POILoader.bundled,
            modelContext: modelContext
        )
        let collectionStore = ContentStore<POICollection>.live(
            collectionName: "collections",
            seed: POICollectionLoader.bundled,
            modelContext: modelContext
        )
        let trophyStore = ContentStore<Trophy>.live(collectionName: "trophies", modelContext: modelContext)
        // Cloud progression sync is Pro + signed-in only (spec: "nécessite
        // le compte") — never constructed for free or signed-out users.
        let userID = authModel.userID
        let sync: ProgressionSyncing? =
            (proEntitlementModel.isProEntitled && userID != nil) ? FirestoreProgressionSync() : nil
        model = ProgressionModel(
            pois: poiStore.items + referenceStore.items,
            collections: collectionStore.items,
            trophies: trophyStore.items,
            modelContext: modelContext,
            sync: sync,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )
        try? await poiStore.syncIfNeeded()
        try? await referenceStore.syncIfNeeded()
        try? await collectionStore.syncIfNeeded()
        try? await trophyStore.syncIfNeeded()
        // Les deux jeux réunis : la carte laisse déjà cocher les POI de la
        // fixture embarquée, donc les exclure d'ici afficherait une progression
        // vide à quelqu'un qui vient d'en trouver trente.
        model?.updateCollections(collectionStore.items)
        model?.updatePOIs(poiStore.items + referenceStore.items)
        model?.updateTrophies(trophyStore.items)
        if let sync, let userID {
            let remoteItems = await sync.fetchAll(uid: userID)
            model?.reconcile(with: remoteItems)
        }
    }
}
