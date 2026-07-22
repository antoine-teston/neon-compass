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
            }
            MapPinsOverlay(pois: model.filteredPOIs, manifest: manifest, viewport: viewport) { poi in
                model.selectedPOI = poi
            }
            PersonalPinsOverlay(pins: model.personalPins, manifest: manifest, viewport: viewport)

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
        .sheet(isPresented: $showPersonalPinList) {
            PersonalPinListSheet(model: model)
        }
        .alert(
            "map.personalPins.addPrompt",
            isPresented: Binding(get: { pendingPinLocation != nil }, set: { if !$0 { pendingPinLocation = nil } })
        ) {
            TextField("map.personalPins.addPrompt", text: $pendingPinTitle)
            Button("map.personalPins.save") {
                if let location = pendingPinLocation, !pendingPinTitle.isEmpty {
                    model.addPersonalPin(at: location, title: pendingPinTitle)
                }
                pendingPinTitle = ""
                pendingPinLocation = nil
            }
            Button("map.personalPins.cancel", role: .cancel) {
                pendingPinLocation = nil
                pendingPinTitle = ""
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
        let contentStore = POIContentStore(
            remote: FirestorePOIRepository(),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = MapModel(pois: contentStore.pois, modelContext: modelContext)
        Task {
            try? await contentStore.syncIfNeeded()
            model?.updatePOIs(contentStore.pois)
        }
    }
}
