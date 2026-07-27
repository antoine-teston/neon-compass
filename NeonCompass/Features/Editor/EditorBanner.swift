#if DEBUG
import SwiftUI

/// Bandeau d'état de l'éditeur.
///
/// Porte le marqueur que `Scripts/check-release-binary.sh` cherche dans le
/// binaire Release : si cette chaîne s'y trouve, c'est que l'éditeur a fui hors
/// de `#if DEBUG`. Une garantie qu'on ne vérifie pas n'en est pas une.
struct EditorBanner: View {
    let draftCount: Int
    let undeliveredCount: Int
    let uid: String?
    let pendingMove: Bool

    static let marker = "NCEditorArmedMarker"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pendingMove
                 ? "Déplacement : appui long sur la nouvelle position"
                 : "Éditeur armé — \(draftCount) brouillon\(draftCount == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))

            if undeliveredCount > 0 {
                Text("\(undeliveredCount) en attente d'envoi")
                    .font(.caption2)
                    .foregroundStyle(NCColor.sunsetOrange)
            }

            // Affiché pour être recopié une fois dans firestore.rules — c'est la
            // seule façon simple de connaître son propre UID.
            if let uid {
                Text(uid)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityIdentifier(Self.marker)
    }
}
#endif
