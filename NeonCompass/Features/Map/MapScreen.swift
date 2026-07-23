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
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel

    private let manifest = TileManifest.load() ?? TileManifest(tileSize: 256, maxZoom: 3, tileCount: 85)

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
            ZStack(alignment: .topTrailing) {
                mapCanvas(model: model)
                MapFilterControls(model: model)
            }
            .sheet(item: Binding(get: { model.selectedPOI }, set: { model.selectedPOI = $0 })) { poi in
                POIDetailView(
                    poi: poi,
                    isFound: model.isFound(poi),
                    onToggleFound: { model.toggleFound(poi) },
                    onDismiss: { model.selectedPOI = nil }
                )
                .presentationDetents([.medium])
            }
        } else {
            HStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    mapCanvas(model: model)
                    MapFilterControls(model: model)
                }
                if let selected = model.selectedPOI {
                    POIDetailView(
                        poi: selected,
                        isFound: model.isFound(selected),
                        onToggleFound: { model.toggleFound(selected) },
                        onDismiss: { model.selectedPOI = nil }
                    )
                    .frame(width: 340)
                    .transition(.move(edge: .trailing))
                }
            }
        }
    }

    private func mapCanvas(model: MapModel) -> some View {
        ZStack(alignment: .topLeading) {
            TiledMapRepresentable(manifest: manifest, viewport: $viewport) { canvasPoint in
                pendingPinLocation = MapGeometry.normalizedPoint(fromCanvasPoint: canvasPoint, manifest: manifest)
                showLongPressMenu = true
            }
            MapPinsOverlay(pois: model.filteredPOIs, manifest: manifest, viewport: viewport) { poi in
                model.selectedPOI = poi
            }
            PersonalPinsOverlay(pins: model.personalPins, manifest: manifest, viewport: viewport)

            if let communityModel {
                ForEach(communityModel.visibleSpots) { spot in
                    let point = spot.position
                    let position = MapGeometry.screenPosition(for: point, manifest: manifest, viewport: viewport)
                    ContributionAnnotationView(
                        spot: spot,
                        onVote: { direction in Task { await communityModel.vote(on: spot, direction: direction) } },
                        onReport: { Task { await communityModel.report(spot, reason: nil) } },
                        onBlockAuthor: {
                            if let authorUid = spot.authorUid { communityModel.block(authorUid: authorUid) }
                        }
                    )
                    .position(position)
                }
            }

            Button {
                showPersonalPinList = true
            } label: {
                Image(systemName: "star.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(16)
        }
        .onAppear {
            communityModel?.refreshBlockedAuthors()
            reattachSyncIfNeeded()
        }
        .sheet(isPresented: $showPersonalPinList) {
            PersonalPinListSheet(model: model)
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
            if communityModel?.contributionsEnabled != false {
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
    }

    private func loadModel() {
        guard model == nil else { return }
        guard FirebaseAvailability.isConfigured else {
            // Firebase not yet activated (Task 7 of Plan 3) — load with no
            // remote content rather than crashing. The map still works with
            // zero POIs; personal pins and "found" tracking are unaffected
            // since those go through FoundEntry/PersonalPin, not this path.
            model = MapModel(pois: [], modelContext: modelContext)
            return
        }
        let contentStore = ContentStore<POI>(
            collectionName: "poi",
            remote: FirestoreContentRepository<POI>(collectionName: "poi"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        // Cloud progression sync is Pro + signed-in only (spec: "nécessite
        // le compte") — never constructed for free or signed-out users.
        let userID = authModel.userID
        let sync: ProgressionSyncing? = (proEntitlementModel.isProEntitled && userID != nil) ? FirestoreProgressionSync() : nil
        model = MapModel(pois: contentStore.items, modelContext: modelContext, sync: sync)
        communityModel = CommunityModel(
            repository: FirestoreContributionRepository(),
            functions: FirebaseContributionFunctions(),
            gateProvider: RemoteConfigCommunityGateProvider(),
            modelContext: modelContext
        )
        Task {
            try? await contentStore.syncIfNeeded()
            model?.updatePOIs(contentStore.items)
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
        let sync = FirestoreProgressionSync()
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
