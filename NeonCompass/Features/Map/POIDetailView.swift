import SwiftUI

struct POIDetailView: View {
    let poi: POI
    let isFound: Bool
    let onToggleFound: () -> Void
    let onDismiss: () -> Void
#if DEBUG
    /// Non nil seulement quand le mode éditeur est armé. La fiche est le seul
    /// endroit où agir sur un POI existant : l'appui long sur le vide reste
    /// dédié à la création (règle de geste unique, cf. spec D5).
    var onEditorMove: (() -> Void)?
    var onEditorDelete: (() -> Void)?
    @State private var showDeleteConfirmation = false
#endif

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

#if DEBUG
            editorActions
#endif
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }

#if DEBUG
    @ViewBuilder
    private var editorActions: some View {
        if onEditorMove != nil || onEditorDelete != nil {
            Divider().overlay(.white.opacity(0.2))
            HStack(spacing: 12) {
                if let onEditorMove {
                    Button("Déplacer", systemImage: "arrow.up.and.down.and.arrow.left.and.right", action: onEditorMove)
                }
                Spacer()
                if onEditorDelete != nil {
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .font(.caption)
            .confirmationDialog("Supprimer ce POI ?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { onEditorDelete?() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Un POI déjà publié deviendra une pierre tombale, pas une suppression.")
            }
        }
    }
#endif
}
