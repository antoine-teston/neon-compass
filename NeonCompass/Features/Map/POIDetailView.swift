import SwiftUI

struct POIDetailView: View {
    let poi: POI
    let isFound: Bool
    let onToggleFound: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(poi.title.en)
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if let note = poi.note {
                Text(note.en)
                    .font(NCTypography.body)
                    .foregroundStyle(.secondary)
            }

            Button {
                onToggleFound()
            } label: {
                Label(
                    isFound ? "poi.detail.found" : "poi.detail.markFound",
                    systemImage: isFound ? "checkmark.circle.fill" : "circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(isFound ? NCColor.neonCyan : NCColor.sunsetMagenta)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }
}
