import SwiftUI
import SwiftData

struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    /// Pour renvoyer au Profil — vers « Mes propositions » après un envoi, et
    /// vers la connexion quand le jeton a expiré en route. Même passerelle que
    /// `SignInToContributeAlert`.
    @Environment(AppModel.self) private var appModel
    @State private var model: MapModel?
    @State private var viewport = MapViewport()
    @State private var focusRequest: MapFocusRequest?
    @State private var showPersonalPinList = false
    /// Le calque du carnet. Un `Bool` à part et non un cas de plus dans
    /// `activeCategories`, qui est un `Set<POICategory>` — y ranger une épingle
    /// serait un mensonge de type.
    @State private var showPersonalPins = true
    @State private var pendingPinLocation: NormalizedPoint?
    @State private var showLongPressMenu = false
    /// Le carnet gratuit est plein. Deux états et non un : le mur DIT ce qui
    /// bloque avant de proposer l'achat — une feuille d'achat qui surgirait sans
    /// explication passerait pour une panne.
    @State private var showNotebookFull = false
    @State private var showPaywall = false
    /// La proposition en cours de pose. Un seul état pour tout le chemin —
    /// placement, envoi, verdict — parce qu'un refus ne referme rien : il faut
    /// retrouver le titre tapé et la catégorie choisie pour pouvoir renvoyer.
    @State private var placement: ContributionPlacement?
    @State private var showSignInToContribute = false
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
    @Environment(FoundStore.self) private var foundStore
    @Environment(PersonalPinStore.self) private var personalPinStore

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
                        showPersonalPins: $showPersonalPins,
                        showPersonalPinList: $showPersonalPinList,
                        showRoutePlanner: $showRoutePlanner
                    )
                    displayControls
                }
                if placement != nil {
                    placementPanel
                        .padding(.bottom, 76)
                } else if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .bottom)
                        // Dégage la tab bar flottante, comme les contrôles
                        // d'affichage juste au-dessus.
                        .padding(.bottom, 76)
                }
            }
            .animation(.snappy, value: model.selection)
            .animation(.snappy, value: placement == nil)
            // En compact le carnet reste une FEUILLE, et c'est ce que veut cette
            // largeur : il n'y a pas de place pour une colonne à côté de la carte.
            // La fiche, elle, est un panneau — c'est une décision mesurée, voir le
            // commentaire du ZStack ci-dessus.
            .sheet(isPresented: $showPersonalPinList) {
                notebook(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(NCColor.nightSky)
            }
            // Même règle qu'en régulier, et pas seulement pour l'allure : ici la
            // feuille se pose AU-DESSUS de la fiche au lieu de la remplacer.
            // Supprimer par balayage, dans le carnet, l'épingle dont la fiche
            // est ouverte derrière laisserait celle-ci sur une référence morte.
            .onChange(of: showPersonalPinList) { _, isShown in
                if isShown { model.selection = nil }
            }
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
                        showPersonalPins: $showPersonalPins,
                        showPersonalPinList: $showPersonalPinList,
                        showRoutePlanner: $showRoutePlanner
                    )
                    displayControls
                }
                // Une seule colonne à droite, jamais deux : la carte est le sujet
                // de l'écran. Le carnet et la fiche partagent donc la MÊME fente,
                // et ouvrir l'un ferme l'autre.
                // Prend la fente avant les deux autres : c'est la surface qui
                // porte un geste en cours, et la seule dont la fermeture perdrait
                // une saisie.
                //
                // Pas de `containerRelativeFrame` ici, contrairement au carnet et
                // à la fiche : le panneau tient en une hauteur courte et connue,
                // il n'a rien à faire défiler et rien à borner.
                if placement != nil {
                    placementPanel
                        .frame(width: 340)
                        .transition(.move(edge: .trailing))
                } else if showPersonalPinList {
                    notebook(model: model)
                        .frame(width: 340)
                        .containerRelativeFrame(.vertical, alignment: .center) { height, _ in
                            height * 0.7
                        }
                        .transition(.move(edge: .trailing))
                } else if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .trailing, width: 340)
                }
            }
            .animation(.snappy, value: placement == nil)
            // `.transition` n'avait jamais joué : rien n'animait la mutation de
            // `selection`, le panneau surgissait et disparaissait d'un coup.
            .animation(.snappy, value: model.selection)
            .animation(.snappy, value: showPersonalPinList)
            // La règle « ouvrir l'un ferme l'autre » dans l'autre sens : sans ça,
            // fermer le carnet ferait réapparaître une fiche que le joueur avait
            // laissée derrière lui.
            .onChange(of: showPersonalPinList) { _, isShown in
                if isShown { model.selection = nil }
            }
        }
    }

    /// Le carnet, écrit une fois pour les deux dispositions — il dit la même
    /// chose qu'il soit posé en feuille ou en panneau. Ce qui diffère, c'est
    /// seulement où l'appelant le pose.
    ///
    /// Taper une ligne fait trois choses dans cet ordre : refermer le carnet,
    /// viser l'épingle, ouvrir sa fiche. La visée avant la sélection, pour que le
    /// recentrage soit déjà lancé quand le panneau arrive par-dessus.
    private func notebook(model: MapModel) -> some View {
        PersonalPinBookView(
            store: personalPinStore,
            game: mapGame,
            isProEntitled: proEntitlementModel.isProEntitled,
            onSelect: { pin in
                showPersonalPinList = false
                focusRequest = MapFocusRequest(position: pin.position)
                model.selection = .pin(pin)
            },
            onDismiss: { showPersonalPinList = false }
        )
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
                // Filtré par CARTE en amont : le moteur ne reçoit que les
                // épingles de la carte affichée, ce qui ferme la fuite d'une
                // carte à l'autre.
                personalPins: personalPinStore.pins(for: mapGame),
                showPersonalPins: showPersonalPins,
                // Les contributions ne concernent que VI : les afficher sur la
                // carte de référence les montrerait à des coordonnées
                // normalisées qui n'y veulent rien dire.
                communitySpots: mapGame == .leonida ? (communityModel?.visibleSpots ?? []) : [],
                // Même garde de carte que les spots publiés : une proposition
                // n'existe que pour la carte du jeu à venir.
                myUnpublishedSpots: mapGame == .leonida ? (communityModel?.myUnpublishedSpots ?? []) : [],
                draftPins: editorDraftPins,
                poisGeneration: model.poisGeneration,
                spotsGeneration: communityModel?.spotsGeneration ?? 0,
                myUnpublishedGeneration: communityModel?.myUnpublishedGeneration ?? 0,
                personalPinsGeneration: personalPinStore.generation,
                foundPOIIDs: model.foundPOIIDs,
                viewport: $viewport,
                focusRequest: $focusRequest,
                placement: placement.map { MapPlacementPin(position: $0.position, category: $0.category) },
                onPlacementMoved: { canvasPoint in
                    placement?.position = MapGeometry.normalizedPoint(fromCanvasPoint: canvasPoint, manifest: manifest)
                },
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
                onTapPOI: { poi in model.selection = .poi(poi) },
                onTapPersonalPin: { pin in model.selection = .pin(pin) },
                onReport: { spot in
                    Task { await communityModel?.report(spot, reason: nil) }
                },
                onBlockAuthor: { spot in
                    if let authorUid = spot.authorUid {
                        // Le pseudo est là MAINTENANT : la RLS de `profiles` ne
                        // laisse lire que sa propre ligne, donc si on ne le
                        // garde pas ici, les réglages n'auront qu'un UUID.
                        communityModel?.block(authorUid: authorUid, handle: spot.authorHandle)
                    }
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
            attachPinSyncIfNeeded()
            loadMyContributionsIfNeeded()
        }
        // Se connecter ne se fait pas depuis la carte : sans cette observation,
        // les propositions d'un compte tout juste rejoint n'apparaîtraient qu'au
        // prochain lancement. Même raison que les deux observations voisines —
        // `RootView` garde les onglets visités montés, donc `.onAppear` ne
        // rejoue pas au retour sur la carte.
        .onChange(of: authModel.userID) { _, _ in loadMyContributionsIfNeeded() }
        // Le retour au premier plan est l'instant où le joueur change
        // d'appareil. Sans cette relecture, le carnet distant ne serait lu
        // qu'une fois par lancement : poser une épingle sur l'iPad puis
        // reprendre l'iPhone resté ouvert ne montrerait rien.
        .onChange(of: scenePhase) { previous, phase in
            guard phase == .active, previous != .active else { return }
            attachPinSyncIfNeeded()
            guard let userID = authModel.userID else { return }
            Task { await personalPinStore.pullRemote(uid: userID) }
            // La modération tranche pendant qu'on est ailleurs : c'est au
            // retour au premier plan qu'une proposition passe d'« en attente »
            // à « approuvée », ou disparaît.
            loadMyContributionsIfNeeded()
        }
        // Les deux conditions de la synchro peuvent devenir vraies pendant que
        // cet écran est déjà monté — c'est même le cas NORMAL : on se connecte
        // et on achète Pro depuis les Réglages, puis on revient à la carte.
        //
        // `.onAppear` ne suffit pas à le voir. `RootView.compactLayout` garde
        // les onglets visités montés dans un ZStack et ne joue que sur
        // l'opacité (c'est délibéré : c'est ce qui préserve le zoom et la
        // position), et changer d'opacité ne redéclenche pas `.onAppear`. Sans
        // ces deux observations, un abonné tout neuf attendrait le prochain
        // lancement pour voir son carnet arriver.
        .onChange(of: authModel.userID) { _, _ in attachPinSyncIfNeeded() }
        .onChange(of: proEntitlementModel.isProEntitled) { _, _ in attachPinSyncIfNeeded() }
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
            model.selection = nil
        }
        // Le mur du plafond. Il DIT ce qui bloque avant de proposer l'achat : une
        // feuille d'achat qui surgirait sans explication passerait pour une panne,
        // et le joueur ne saurait pas pourquoi son épingle n'est pas apparue.
        .alert("map.pins.full.title", isPresented: $showNotebookFull) {
            Button("map.pins.full.upgrade") { showPaywall = true }
            Button("map.pins.full.cancel", role: .cancel) {}
        } message: {
            Text("map.pins.full.message")
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
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
        .confirmationDialog("map.longPress.menuTitle", isPresented: $showLongPressMenu, titleVisibility: .visible) {
            Button("map.longPress.addPersonalPin") {
                guard let location = pendingPinLocation else { return }
                pendingPinLocation = nil
                // L'épingle existe TOUT DE SUITE, et sa fiche s'ouvre dessus,
                // champ de titre prêt à recevoir la frappe. On peut en poser cinq
                // en dix secondes manette en main, ou nommer soigneusement — au
                // choix, et sans traverser une deuxième surface.
                //
                // Ce qui disparaît avec l'alerte : un « Enregistrer » qui ne
                // faisait rien, en silence, quand le champ était vide.
                if let pin = personalPinStore.create(
                    at: location,
                    game: mapGame,
                    isProEntitled: proEntitlementModel.isProEntitled
                ) {
                    model.selection = .pin(pin)
                } else {
                    showNotebookFull = true
                }
            }
            // Le coupe-circuit communautaire échoue OUVERT (c'est un
            // interrupteur d'urgence sur une capacité qui existe). Le drapeau
            // serveur, lui, échoue fermé : sans submitContribution déployée,
            // ce bouton mènerait à une erreur à chaque fois.
            //
            // VI SEULEMENT. La carte de référence est intégralement documentée
            // depuis dix ans : il n'y a rien à y découvrir, et toute la raison
            // d'être des contributions est la carte que personne n'a encore
            // parcourue. C'est aussi ce qui dispense `contributions` d'une
            // colonne de jeu — il est connu par construction.
            if mapGame == .leonida, serverFeatures.isEnabled, communityModel?.contributionsEnabled != false {
                Button("map.longPress.proposeSpot") {
                    if authModel.userID != nil, let location = pendingPinLocation {
                        placement = ContributionPlacement(
                            position: location,
                            // Arme le cooldown AVANT le réseau : deux
                            // propositions d'affilée sur le même téléphone ne
                            // partent pas pour rien.
                            lastSubmissionAt: communityModel?.lastSubmissionAt
                        )
                        // Sort l'épingle de sous le panneau. Un appui long dans
                        // le tiers bas la poserait pile là où le panneau va
                        // venir, et on ajusterait à l'aveugle.
                        focusRequest = MapFocusRequest(position: location)
                    } else {
                        // L'`else` qui manquait. Le bouton reste VISIBLE hors
                        // connexion — le masquer priverait un visiteur de la
                        // seule occasion d'apprendre que la contribution existe
                        // — mais il dit maintenant ce qui bloque, au lieu de
                        // refermer le menu sans rien faire.
                        showSignInToContribute = true
                    }
                    pendingPinLocation = nil
                }
            }
            Button("map.longPress.cancel", role: .cancel) {
                pendingPinLocation = nil
            }
        }
        .signInToContributeAlert(isPresented: $showSignInToContribute)
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
    private func detailPanel(_ selection: MapSelection, model: MapModel, edge: Edge, width: CGFloat? = nil) -> some View {
        panelContent(selection, model: model)
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
                        model.selection = nil
                    }
            )
            // Une feuille rendait la carte derrière elle invisible à VoiceOver
            // et répondait au geste d'échappement. Un panneau posé dans l'arbre
            // ne fait ni l'un ni l'autre de lui-même : sans ces deux lignes, le
            // gain de fluidité se paierait en accessibilité.
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { model.selection = nil }
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

    /// Le panneau de soumission, écrit une fois pour les deux dispositions.
    ///
    /// Il ne passe PAS par `detailPanel` : celui-ci congédie au balayage et
    /// s'échappe à l'`escape`, ce qui est juste pour une fiche en lecture et faux
    /// ici — un balayage de trop jetterait un titre en cours de frappe. La
    /// sortie de ce panneau est explicite, par 「Annuler」.
    @ViewBuilder
    private var placementPanel: some View {
        if placement != nil, let communityModel {
            ContributionPlacementPanel(
                placement: Binding(
                    get: { placement ?? ContributionPlacement(position: NormalizedPoint(x: 0.5, y: 0.5)) },
                    set: { placement = $0 }
                ),
                style: mapStyle,
                onSubmit: { submitPlacement(communityModel) },
                onCancel: { placement = nil },
                onSeeMine: {
                    placement = nil
                    appModel.selectedTab = .profile
                },
                onSignIn: {
                    placement = nil
                    appModel.selectedTab = .profile
                }
            )
            .accessibilityAddTraits(.isModal)
        }
    }

    /// Relit MES propositions, celles que la carte dessine en attente.
    ///
    /// Échoue en silence — même parti que `loadMyVotes` : sans elles, la carte
    /// est celle de tout le monde, ce qui est dégradé mais juste. Une alerte
    /// interromprait sans rien offrir à faire.
    private func loadMyContributionsIfNeeded() {
        guard let communityModel, let userID = authModel.userID else { return }
        Task { await communityModel.loadMyContributions(uid: userID) }
    }

    private func submitPlacement(_ communityModel: CommunityModel) {
        guard var current = placement else { return }
        current.beganSending()
        placement = current
        let sent = current
        Task {
            do {
                try await communityModel.submit(
                    category: sent.category,
                    title: sent.trimmedTitle,
                    position: sent.position,
                    languageCode: Self.currentLanguageCode()
                )
                placement?.succeeded()
                // Relit MES propositions : c'est ce qui fait apparaître
                // l'épingle en attente sur la carte, sans attendre la
                // reconstruction des fragments.
                if let uid = authModel.userID {
                    await communityModel.loadMyContributions(uid: uid)
                }
            } catch {
                // Le panneau reste ouvert avec sa saisie. Toute erreur non
                // typée devient `.failed` plutôt que d'être avalée — c'est
                // exactement le `try?` qu'on retire ici.
                placement?.failed(
                    with: (error as? ContributionSubmissionError) ?? .failed,
                    now: Date()
                )
            }
        }
    }

    /// Ce que le panneau montre — deux natures, une seule fente. Les
    /// comportements de panneau (congédiement au balayage, `.isModal`, geste
    /// d'échappement, cadre borné) sont posés une fois pour les deux par
    /// `detailPanel` : ils décrivent le panneau, pas ce qu'on y met.
    @ViewBuilder
    private func panelContent(_ selection: MapSelection, model: MapModel) -> some View {
        switch selection {
        case .poi(let poi):
            poiDetail(poi, model: model)
        case .pin(let pin):
            PersonalPinCardView(
                pin: pin,
                store: personalPinStore,
                onDismiss: { model.selection = nil },
                onDelete: {
                    // Vider la sélection AVANT la suppression : le panneau tient
                    // une référence, et un objet SwiftData effacé sous elle est un
                    // plantage en attente.
                    model.clearSelectionIfPin(pin)
                    personalPinStore.delete(pin)
                }
            )
        }
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
            onDismiss: { model.selection = nil }
        )
#if DEBUG
        if editorModel.isArmed {
            view.onEditorMove = {
                editorModel.beginMove(poiID: poi.id)
                model.selection = nil
            }
            view.onEditorDelete = {
                editorModel.delete(poiID: poi.id)
                model.selection = nil
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
            model = MapModel(pois: pois(for: mapGame), modelContext: modelContext, found: foundStore)
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
        model = MapModel(pois: pois(for: mapGame), modelContext: modelContext, found: foundStore, sync: sync)
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

    /// Même rattrapage, pour le carnet.
    ///
    /// `PersonalPinStore` est construit dans `NeonCompassApp`, donc bien avant
    /// que `ProEntitlementModel.refresh()` n'ait répondu : sans cet appel depuis
    /// `.onAppear`, un abonné verrait son carnet rester local jusqu'au prochain
    /// lancement. Sans effet et sans coût tant que le droit Pro ou le compte
    /// manquent, et idempotent ensuite — c'est `attachSyncIfNeeded` qui le
    /// garantit, pas l'appelant.
    private func attachPinSyncIfNeeded() {
        guard proEntitlementModel.isProEntitled, let userID = authModel.userID else { return }
        let sync = SupabasePersonalPinSync()
        guard personalPinStore.attachSyncIfNeeded(sync) else { return }
        Task {
            let remoteItems = await sync.fetchAll(uid: userID)
            personalPinStore.reconcile(with: remoteItems)
        }
    }
}

extension MapScreen {
    static func currentLanguageCode() -> String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let supported = ["en", "fr", "es", "it", "de"]
        return supported.contains(code) ? code : "en"
    }
}
