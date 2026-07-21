import SwiftUI

struct MapPinsOverlay: View {
    let pois: [POI]
    let manifest: TileManifest
    let viewport: MapViewport
    let onTap: (POI) -> Void

    var body: some View {
        ForEach(pois) { poi in
            let position = MapGeometry.screenPosition(for: poi.position, manifest: manifest, viewport: viewport)
            Button {
                onTap(poi)
            } label: {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(NCColor.neonCyan)
                    .shadow(color: NCColor.neonCyan.opacity(0.6), radius: 4)
            }
            .position(position)
            .accessibilityLabel(Text(poi.title.en))
        }
    }
}
