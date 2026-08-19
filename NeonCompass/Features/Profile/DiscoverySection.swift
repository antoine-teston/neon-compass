import SwiftUI
import SwiftData

/// La Découverte, embarquée dans le Profil : la carte à deux anneaux, et la
/// feuille de détail qu'elle ouvre.
///
/// Anciennement `ProgressionSection`. Porte son propre chargement plutôt que de
/// le recevoir. Deux mécanismes subtils en dépendent —
/// `RootView.hydrateWidgetSummaryFromCache()` construit un second
/// `ProgressionModel` au lancement pour alimenter le widget, et
/// `reattachSyncIfNeeded()` referme une course entre l'entitlement Pro et la
/// construction du modèle. Tous deux sont nés de bugs réels ; ne pas les
/// remanier en même temps qu'autre chose.
struct DiscoverySection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSummaryCoordinator.self) private var widgetSummaryCoordinator
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(FoundStore.self) private var foundStore
    @State private var model: ProgressionModel?
    @State private var showChallenges = false

    var body: some View {
        Group {
            if let model {
                DiscoveryCard(
                    state: DiscoveryState(
                        challenges: model.challenges,
                        foundCountByGame: Dictionary(
                            uniqueKeysWithValues: Game.allCases.map { ($0, model.foundCount(for: $0)) }
                        )
                    ),
                    onOpenChallenges: { showChallenges = true }
                )
                .sheet(isPresented: $showChallenges) {
                    ChallengesSheet(model: model)
                }
            } else {
                ProgressView()
            }
        }
        // Cf. FeedScreen : accrochée au ProgressView, cette tâche s'annulait
        // elle-même dès que `model` était assigné. Les synchronisations qui
        // suivent ne repartaient donc jamais — l'écran vivait sur le seul socle
        // embarqué, et l'overlay distant ne s'appliquait pas : corriger un POI
        // publié sans repasser par l'App Store, tout l'intérêt de l'overlay, ne
        // marchait pas ici.
        .task { await loadModel() }
        .onAppear {
            model?.refreshFoundState()
            reattachSyncIfNeeded()
        }
        // Le déclencheur qui manquait, et le cœur du correctif.
        //
        // `.onAppear` ci-dessus ne se rejoue JAMAIS sur iPhone : `compactLayout`
        // garde les onglets visités montés dans un `ZStack` et ne joue que sur
        // l'opacité (délibéré — c'est ce qui préserve le zoom et la recherche de
        // la carte), et changer d'opacité n'est pas réapparaître. Cocher trente
        // lieux sur la carte laissait donc les anneaux, les compteurs et le
        // résumé du widget figés sur la première visite du Profil, jusqu'au
        // prochain lancement.
        //
        // Cette vue reste ÉVALUÉE quand elle est masquée — c'est ce qui rend
        // `onChange` fiable ici là où `onAppear` ne l'est pas. Les défis sont un
        // état dérivé STOCKÉ (mesuré : le calculer à la lecture rebalayait tout le
        // tableau de POI à chaque accès), donc il faut bien dire quand recalculer.
        .onChange(of: foundStore.foundIDs) { _, _ in
            model?.refreshFoundState()
        }
    }

    /// Closes the race where `loadModel()` ran once before
    /// `ProEntitlementModel.refresh()` completed at app launch, capturing
    /// `sync == nil` permanently for this screen instance (SwiftUI retains
    /// `@State` across iPad tab switches, so `loadModel()` itself never
    /// re-runs). Cheap no-op whenever the Pro/auth gate is still false.
    private func reattachSyncIfNeeded() {
        guard let model, proEntitlementModel.isProEntitled, let userID = authModel.userID else { return }
        let sync = SupabaseProgressionSync()
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
        // Cloud progression sync is Pro + signed-in only (spec: "nécessite
        // le compte") — never constructed for free or signed-out users.
        let userID = authModel.userID
        let sync: ProgressionSyncing? =
            (proEntitlementModel.isProEntitled && userID != nil) ? SupabaseProgressionSync() : nil
        model = ProgressionModel(
            poisByGame: [.leonida: poiStore.items, .reference: referenceStore.items],
            collections: collectionStore.items,
            modelContext: modelContext,
            found: foundStore,
            sync: sync,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )
        try? await poiStore.syncIfNeeded()
        try? await referenceStore.syncIfNeeded()
        try? await collectionStore.syncIfNeeded()
        // Les deux jeux SÉPARÉS et non concaténés : c'est la seule chose qui
        // permette de compter les lieux d'un jeu donné. Un POI du volet à venir
        // a `collection: nil` par défaut, donc il ne se rattache à aucun défi —
        // fusionner les deux tableaux rendait son compte inatteignable, et le
        // volet éternellement à zéro.
        model?.updateCollections(collectionStore.items)
        model?.updatePOIs([.leonida: poiStore.items, .reference: referenceStore.items])
        if let sync, let userID {
            let remoteItems = await sync.fetchAll(uid: userID)
            model?.reconcile(with: remoteItems)
        }
    }
}
