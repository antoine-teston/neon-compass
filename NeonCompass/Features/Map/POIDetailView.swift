import SwiftUI

struct POIDetailView: View {
    let poi: POI
    let isFound: Bool
    let onToggleFound: () -> Void
    let onDismiss: () -> Void

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(poi.title.resolved(for: currentLanguageCode))
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
                Text(note.resolved(for: currentLanguageCode))
                    .font(NCTypography.body)
                    .foregroundStyle(.secondary)
            }

            Button {
                onToggleFound()
            } label: {
                Group {
                    if isFound {
                        Label("poi.detail.found", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("poi.detail.markFound", systemImage: "circle")
                    }
                }
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
