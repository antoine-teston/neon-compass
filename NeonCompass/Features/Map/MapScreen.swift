import SwiftUI
import SwiftData

struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model: MapModel?
    @State private var viewport = MapViewport()
    @State private var showPersonalPinList = false
    @State private var pendingPinLocation: NormalizedPoint?
    @State private var pendingPinTitle = ""
    @State private var showLongPressMenu = false
    @State private var showPersonalPinAlert = false
    @State private var pendingContributionLocation: NormalizedPoint?
    @State private var communityModel: CommunityModel?
    @State private var showRoutePlanner = false
    // Volontairement NON persisté : l'app doit rouvrir sur l'habillage Neon
    // Compass, qui est son identité (voir MapStyle).
    @State private var mapStyle: MapStyle = .neon
    // Par défaut sur la carte de référence : c'est la seule des deux à avoir
    // du contenu placé aujourd'hui. Ouvrir sur le placeholder donnerait une
    // carte sans le moindre pin. À rebasculer sur `.leonida` le jour où le
    // contenu éditorial aura de vraies positions.
    @State private var mapGame: MapGame = .reference
    @State private var remotePOIs: [POI] = []
#if DEBUG
    /// Mode éditeur interne : compilé hors du binaire soumis. Construit tout de
    /// suite plutôt qu'à l'armement — il ne coûte rien tant qu'il dort, et son
    /// état doit survivre aux bascules d'onglet comme le reste de l'écran.
    @State private var editorModel = EditorModel(store: EditorDraftRouter(
        remote: SupabaseEditorDraftStore(),
        local: FileEditorDraftStore(),
        isRemoteUsable: { EditorRemoteAvailability.isUsable }
    ))
#endif

    /// Socle embarqué de la carte de référence, patché par l'overlay distant dès
    /// qu'il arrive. Initialisé au socle nu pour que la carte soit explorable au
    /// premier lancement, sans réseau — et si Firebase n'est pas configuré, ça
    /// reste la valeur définitive.
    @State private var referencePOIs: [POI] = POILoader.bundled
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures

    private let manifest = MapManifest.load() ?? MapManifest(size: 2048)

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                ProgressView()
                    .task { loadModel() }
            }
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    @ViewBuilder
    private func content(model: MapModel) -> some View {
        if sizeClass == .compact {
            // La fiche n'est plus une feuille présentée par le système, mais
            // un panneau dans l'arbre de vues — le même qu'en régulier, posé
            // en bas au lieu de la droite.
            //
            // Mesuré sur iPhone : présenter une feuille coûtait ~60 ms à
            // l'ouverture ET ~46 ms à la fermeture, soit quatre images perdues
            // à chaque aller-retour, QUEL QUE SOIT son contenu — une feuille
            // vide coûtait exactement autant qu'une fiche complète, et le
            // Release n'y changeait rien. Le même contenu en panneau, tel que
            // l'iPad l'affichait déjà, ouvre et ferme en 16,7 ms, c'est-à-dire
            // sans perdre une seule image.
            ZStack(alignment: .bottom) {
                ZStack(alignment: .top) {
                    mapCanvas(model: model)
                    MapFilterControls(
                        model: model,
                        showPersonalPinList: $showPersonalPinList,
                        showRoutePlanner: $showRoutePlanner
                    )
                    displayControls
                }
                if let selected = model.selectedPOI {
                    detailPanel(selected, model: model, edge: .bottom)
                        // Dégage la tab bar flottante, comme les contrôles
                        // d'affichage juste au-dessus.
                        .padding(.bottom, 76)
                }
            }
            .animation(.snappy, value: model.selectedPOI)
        } else {
            // Le panneau FLOTTE au-dessus de la carte au lieu de la pousser.
            //
            // Dans un HStack, ouvrir une fiche réduisait la largeur de la carte
            // de 340 pt — et cette largeur s'anime. Mesuré : 29 passages dans
            // `layoutSubviews` de la vue de défilement pour une seule ouverture,
            // soit 29 recalculs d'échelle de couverture et d'encarts de
            // centrage, sur une vue hébergée de 2048×2048 portant des centaines
            // de pastilles. C'était toute la saccade.
            //
            // La surimpression est aussi ce que dit la langue visuelle du
            // projet : le chrome en Liquid Glass flotte au-dessus du contenu —
            // c'est déjà le parti pris de la barre d'onglets et des contrôles
            // de carte, et la raison pour laquelle la carte passe sous les
            // safe areas.
            ZStack(alignment: .trailing) {
                ZStack(alignment: .top) {
                    mapCanvas(model: model)
                    MapFilterControls(
                        model: model,
                        showPersonalPinList: $showPersonalPinList,
                        showRoutePlanner: $showRoutePlanner
                    )
                    displayControls
                }
                if let selected = model.selectedPOI {
                    detailPanel(selected, model: model, edge: .trailing, width: 340)
                }
            }
            // `.transition` n'avait jamais joué : rien n'animait la mutation de
            // `selectedPOI`, le panneau surgissait et disparaissait d'un coup.
            .animation(.snappy, value: model.selectedPOI)
        }
    }

    /// Ancré en bas à droite : à portée du pouce, et hors du bandeau haut déjà
    /// occupé par la recherche et les filtres. Le décalage bas dégage la tab
    /// bar flottante (~72 pt au-dessus de la safe area, cf. CompactTabBar).
    private var displayControls: some View {
        var controls = MapDisplayControls(game: $mapGame, style: $mapStyle)
#if DEBUG
        if editorModel.canArm(on: mapGame) {
            controls.editorArmed = Binding(
                get: { editorModel.isArmed },
                set: { editorModel.setArmed($0, on: mapGame) }
            )
        }
#endif
        return controls
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16)
            .padding(.bottom, 76)
    }

    private func mapCanvas(model: MapModel) -> some View {
        ZStack(alignment: .topLeading) {
            TiledMapRepresentable(
                manifest: manifest,
                game: mapGame,
                style: mapStyle,
                pois: model.filteredPOIs,
                personalPins: model.personalPins,
                communitySpots: communityModel?.visibleSpots ?? [],
                draftPins: editorDraftPins,
                poisGeneration: model.poisGeneration,
                spotsGeneration: communityModel?.spotsGeneration ?? 0,
                personalPinsGeneration: model.personalPinsGeneration,
                isFound: model.isFound,
                viewport: $viewport,
                onLongPress: { canvasPoint in
                    let normalized = MapGeometry.normalizedPoint(fromCanvasPoint: canvasPoint, manifest: manifest)
#if DEBUG
                    // L'éditeur armé prend la main sur le menu habituel : c'est
                    // la règle de geste — appui long sur le vide = créer.
                    if editorModel.handleLongPress(at: normalized) != .ignored { return }
#endif
                    pendingPinLocation = normalized
                    showLongPressMenu = true
                },
                onTapPOI: { poi in model.selectedPOI = poi },
                onVote: { spot, direction in
                    Task { await communityModel?.vote(on: spot, direction: direction) }
                },
                onReport: { spot in
                    Task { await communityModel?.report(spot, reason: nil) }
                },
                onBlockAuthor: { spot in
                    if let authorUid = spot.authorUid { communityModel?.block(authorUid: authorUid) }
                },
                onAdopt: adoptHandler
            )
            // La carte passe SOUS la barre d'état et sous la tab bar : le
            // chrome est en Liquid Glass, il est fait pour flotter au-dessus du
            // contenu. Sans ça la vue zoomable est amputée des safe areas (778
            // pt sur 874 mesurés en iPhone 17 Pro), ce qui laissait une bande
            // morte en haut et en bas même à pleine échelle.
            .ignoresSafeArea()
        }
        .onAppear {
            communityModel?.refreshBlockedAuthors()
            reattachSyncIfNeeded()
        }
        .onChange(of: mapGame) { _, newGame in
#if DEBUG
            // Désarme si la carte d'arrivée n'accepte pas d'ajouts, avant tout
            // le reste : un appui long entre-temps poserait un POI aux
            // coordonnées de l'autre carte.
            editorModel.mapChanged(to: newGame)
#endif
            // Les deux cartes ont des jeux de POI disjoints : changer de carte
            // change la source, pas seulement l'image de fond.
            model.updatePOIs(pois(for: newGame))
            model.selectedPOI = nil
        }
        .sheet(isPresented: $showPersonalPinList) {
            PersonalPinListSheet(model: model)
        }
        .sheet(isPresented: $showRoutePlanner) {
            RoutePlannerSheet(
                route: RoutePlanner.greedyRoute(
                    // Deliberately computed from the full, unfiltered `pois`
                    // array rather than `filteredPOIs` — the route planner
                    // must never be silently narrowed by the map's category
                    // chips or search text (see plan 6b-2 final-review fix).
                    from: model.pois.filter { $0.category == .collectible && $0.position != nil && !model.isFound($0) }
                ),
                languageCode: Self.currentLanguageCode()
            )
        }
        .alert(
            "map.personalPins.addPrompt",
            isPresented: $showPersonalPinAlert
        ) {
            TextField("map.personalPins.addPrompt", text: $pendingPinTitle)
            Button("map.personalPins.save") {
                if let location = pendingPinLocation, !pendingPinTitle.isEmpty {
                    model.addPersonalPin(at: location, title: pendingPinTitle)
                }
                pendingPinTitle = ""
                pendingPinLocation = nil
                showPersonalPinAlert = false
            }
            Button("map.personalPins.cancel", role: .cancel) {
                pendingPinLocation = nil
                pendingPinTitle = ""
                showPersonalPinAlert = false
            }
        }
        .confirmationDialog("map.longPress.menuTitle", isPresented: $showLongPressMenu, titleVisibility: .visible) {
            Button("map.longPress.addPersonalPin") {
                // Arms the alert now that the user explicitly chose this option —
                // pendingPinLocation was already set on long-press.
                showPersonalPinAlert = true
            }
            // Le coupe-circuit communautaire échoue OUVERT (c'est un
            // interrupteur d'urgence sur une capacité qui existe). Le drapeau
            // serveur, lui, échoue fermé : sans submitContribution déployée,
            // ce bouton mènerait à une erreur à chaque fois.
            if serverFeatures.isEnabled, communityModel?.contributionsEnabled != false {
                Button("map.longPress.proposeSpot") {
                    if authModel.userID != nil {
                        pendingContributionLocation = pendingPinLocation
                    }
                    pendingPinLocation = nil
                }
            }
            Button("map.longPress.cancel", role: .cancel) {
                pendingPinLocation = nil
            }
        }
        .sheet(item: Binding(
            get: { pendingContributionLocation.map { ContributionLocationBox(location: $0) } },
            set: { pendingContributionLocation = $0?.location }
        )) { box in
            if let communityModel {
                ContributionSubmissionSheet(
                    position: box.location,
                    onSubmit: { category, title in
                        try? await communityModel.submit(category: category, title: title, position: box.location, languageCode: Self.currentLanguageCode())
                        pendingContributionLocation = nil
                    },
                    onDismiss: { pendingContributionLocation = nil }
                )
                .presentationDetents([.medium])
            }
        }
        // `#if` postfix (SE-0308) : l'éditeur ne laisse aucune trace dans la
        // chaîne de modificateurs en Release, sans AnyView ni indirection.
        #if DEBUG
        .modifier(EditorLayer(model: editorModel, uid: authModel.userID))
        #endif
    }

    // MARK: - Mode éditeur (debug uniquement)

    /// Les deux accès ci-dessous isolent la compilation conditionnelle : le
    /// corps de `mapCanvas` reste lisible, et en Release ils se réduisent à une
    /// liste vide et un nil, sur des types qui existent dans les deux
    /// configurations.
    private var editorDraftPins: [DraftPin] {
#if DEBUG
        editorModel.draftPins
#else
        []
#endif
    }

    /// La fiche telle qu'elle est POSÉE sur la carte : en bas en compact, à
    /// droite en régulier. Une seule écriture pour les deux, parce que les deux
    /// doivent se comporter pareil — c'est justement ce qui n'était pas vrai
    /// tant que le compact passait par une feuille système.
    ///
    /// Ce que la feuille rendait gratuitement, et qu'il faut donc rendre ici :
    /// le congédiement au balayage, l'isolement du contenu derrière pour
    /// VoiceOver, et le geste d'échappement.
    private func detailPanel(_ poi: POI, model: MapModel, edge: Edge, width: CGFloat? = nil) -> some View {
        poiDetail(poi, model: model)
            .frame(width: width)
            // Le panneau flotte AU-DESSUS de la carte : sans forme explicite, le
            // verre peint sans rien intercepter et un tap le traverserait pour
            // atteindre un pin situé derrière.
            .contentShape(.rect)
            // Ce qui s'ouvre d'un geste se ferme d'un geste, vers le bord d'où
            // le panneau est venu. La distance minimale laisse les boutons du
            // panneau tranquilles.
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { drag in
                        let travelled = edge == .bottom ? drag.translation.height : drag.translation.width
                        guard travelled > 60 else { return }
                        model.selectedPOI = nil
                    }
            )
            // Une feuille rendait la carte derrière elle invisible à VoiceOver
            // et répondait au geste d'échappement. Un panneau posé dans l'arbre
            // ne fait ni l'un ni l'autre de lui-même : sans ces deux lignes, le
            // gain de fluidité se paierait en accessibilité.
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { model.selectedPOI = nil }
            // Borne ce qui est PROPOSÉ à la fiche, sans le lui imposer.
            //
            // La feuille système plafonnait la fiche à mi-écran et faisait
            // défiler le reste. Il faut le refaire, mais pas avec un
            // `.frame(maxHeight:)` posé sur la fiche : un cadre qui ne fixe
            // qu'un maximum prend toute la hauteur proposée jusqu'à ce
            // maximum, et une note de deux lignes se retrouvait centrée au
            // milieu du vide.
            //
            // Ici le cadre est TRANSPARENT et la fiche s'y aligne sur le bord
            // d'où elle vient : le vide éventuel laisse voir la carte, et ne
            // capte aucun geste puisque la forme de frappe reste celle de la
            // fiche, posée plus haut. La fiche, elle, reçoit une proposition
            // bornée — ce qui permet à sa note de choisir entre sa hauteur
            // naturelle et une version défilante.
            .containerRelativeFrame(.vertical, alignment: edge == .bottom ? .bottom : .center) { height, _ in
                height * 0.55
            }
            .transition(.move(edge: edge))
    }

    /// Fiche d'un POI, augmentée des actions d'édition quand l'éditeur est armé.
    /// Construite ici plutôt qu'au site d'appel : les deux dispositions (feuille
    /// en compact, panneau latéral en régulier) partagent ainsi exactement la
    /// même fiche.
    private func poiDetail(_ poi: POI, model: MapModel) -> some View {
        var view = POIDetailView(
            poi: poi,
            isFound: model.isFound(poi),
            onToggleFound: { model.toggleFound(poi) },
            onDismiss: { model.selectedPOI = nil }
        )
#if DEBUG
        if editorModel.isArmed {
            view.onEditorMove = {
                editorModel.beginMove(poiID: poi.id)
                model.selectedPOI = nil
            }
            view.onEditorDelete = {
                editorModel.delete(poiID: poi.id)
                model.selectedPOI = nil
            }
        }
#endif
        return view
    }

    private var adoptHandler: ((Contribution) -> Void)? {
#if DEBUG
        guard editorModel.isArmed else { return nil }
        return { spot in editorModel.adopt(spot) }
#else
        nil
#endif
    }


    /// Fixture embarquée de la carte de référence
    /// (`Resources/POI/seed-poi.json`, produite par
    /// `tools/basemap/gtav-poi.mjs`). `static let` : décodée une seule fois
    /// par lancement, le fichier pèse ~200 Ko.
    ///
    /// `POILoader.loadSeed` existait depuis le plan 2 mais n'avait plus aucun
    /// appelant depuis que le plan 3 a branché la carte sur Firestore — d'où
    /// une carte de référence sans le moindre POI.
    /// Le cache vit maintenant sur `POILoader` : l'écran de progression a besoin
    /// de la même fixture pour ses dénominateurs, et deux `static let` séparés
    /// en auraient fait deux parses.
    private func pois(for game: MapGame) -> [POI] {
        MapModel.pois(for: game, remote: remotePOIs, reference: referencePOIs)
    }

    private func loadModel() {
        guard model == nil else { return }
        guard SupabaseClientProvider.isConfigured else {
            // Aucun projet configuré : pas de contenu distant, mais la carte de
            // référence reste explorable. Les épingles personnelles et le
            // marquage « trouvé » ne sont pas concernés — ils passent par
            // FoundEntry/PersonalPin, pas par ce chemin.
            model = MapModel(pois: pois(for: mapGame), modelContext: modelContext)
            return
        }
        let contentStore = ContentStore<POI>.live(
            collectionName: "poi",
            modelContext: modelContext
        )
        // Deuxième store, collection distincte : les positions de la fixture
        // sont normalisées sur la carte de référence. Les mêler au contenu du
        // jeu à venir poserait des centaines de pins à des endroits qui ne
        // veulent rien dire — cf. `MapModel.pois(for:remote:reference:)`.
        let referenceStore = ContentStore<POI>.live(
            collectionName: "poi_gtav",
            seed: POILoader.bundled,
            modelContext: modelContext
        )
        // Cloud progression sync is Pro + signed-in only (spec: "nécessite
        // le compte") — never constructed for free or signed-out users.
        let userID = authModel.userID
        let sync: ProgressionSyncing? = (proEntitlementModel.isProEntitled && userID != nil) ? SupabaseProgressionSync() : nil
        remotePOIs = contentStore.items
        referencePOIs = referenceStore.items
        model = MapModel(pois: pois(for: mapGame), modelContext: modelContext, sync: sync)
        communityModel = CommunityModel.live(modelContext: modelContext)
        Task {
            try? await contentStore.syncIfNeeded()
            try? await referenceStore.syncIfNeeded()
            remotePOIs = contentStore.items
            referencePOIs = referenceStore.items
            model?.updatePOIs(pois(for: mapGame))
            await communityModel?.loadApprovedSpots()
            await communityModel?.refreshContributionsEnabled()
            if let sync, let userID {
                let remoteItems = await sync.fetchAll(uid: userID)
                model?.reconcile(with: remoteItems)
            }
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
}

private struct ContributionLocationBox: Identifiable {
    let location: NormalizedPoint
    var id: String { "\(location.x)-\(location.y)" }
}

extension MapScreen {
    static func currentLanguageCode() -> String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let supported = ["en", "fr", "es", "it", "de"]
        return supported.contains(code) ? code : "en"
    }
}
