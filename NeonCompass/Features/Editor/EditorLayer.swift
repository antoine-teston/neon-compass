#if DEBUG
import SwiftUI

/// Tout ce que le mode éditeur ajoute par-dessus la carte : le bandeau d'état et
/// la grille de catégories.
///
/// Regroupé dans un `ViewModifier` plutôt qu'étalé dans `MapScreen` pour que le
/// branchement tienne en une ligne — et pour qu'en Release il n'en reste
/// littéralement rien, le `#if` postfix du site d'appel supprimant l'appel
/// entier.
struct EditorLayer: ViewModifier {
    let model: EditorModel
    let uid: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if model.isArmed {
                    EditorBanner(
                        draftCount: model.draftPins.count,
                        undeliveredCount: model.undeliveredCount,
                        uid: uid,
                        pendingMove: model.pendingMovePOIID != nil
                    )
                    .padding(.top, 108)
                    // Relancé à chaque capture : `waitForPendingWrites` ne
                    // rend la main qu'une fois la file vidée, donc une tâche
                    // par palier de compteur suffit à tenir l'affichage à jour.
                    .task(id: model.undeliveredCount) { await model.awaitDelivery() }
                }
            }
            .sheet(item: Binding(
                get: { model.pendingCapture.map(EditorCaptureBox.init) },
                set: { model.pendingCapture = $0?.location }
            )) { box in
                EditorCategoryGrid(
                    onPick: { model.capture(category: $0, at: box.location) },
                    onCancel: { model.pendingCapture = nil }
                )
                .presentationDetents([.height(320)])
            }
    }
}

/// `sheet(item:)` exige un `Identifiable` ; une position n'en est pas un.
private struct EditorCaptureBox: Identifiable {
    let location: NormalizedPoint
    var id: String { "\(location.x)-\(location.y)" }
}
#endif
