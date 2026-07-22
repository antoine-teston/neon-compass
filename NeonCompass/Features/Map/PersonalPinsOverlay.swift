import SwiftUI

struct PersonalPinsOverlay: View {
    let pins: [PersonalPin]
    let manifest: TileManifest
    let viewport: MapViewport

    var body: some View {
        ForEach(pins) { pin in
            let point = NormalizedPoint(x: pin.x, y: pin.y)
            let position = MapGeometry.screenPosition(for: point, manifest: manifest, viewport: viewport)
            Image(systemName: "star.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(NCColor.sunsetOrange)
                .position(position)
                .accessibilityLabel(Text(pin.title))
        }
    }
}
