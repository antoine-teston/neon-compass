import SwiftUI

/// L'invite de désignation du départ : un tap sur la carte choisit le lieu le
/// plus proche, et la tournée part de là. Muet — il n'affiche que du texte fixe
/// et remonte l'annulation.
///
/// Distinct de `RouteModePanel` parce qu'il n'y a pas encore de tournée à cet
/// instant : celui-là s'articule autour d'un `RouteRun`, celui-ci le précède.
struct RouteStartPickPanel: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("map.routeMode.pickStart.title")
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
                Spacer()
            }
            Text("map.routeMode.pickStart.hint")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Button("map.routeMode.pickStart.cancel", action: onCancel)
                .buttonStyle(.glass)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }
}
