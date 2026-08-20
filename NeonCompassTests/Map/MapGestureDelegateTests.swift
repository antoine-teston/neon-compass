import SwiftUI
import Testing
import UIKit
@testable import NeonCompass

/// `Coordinator` sert de délégué `UIGestureRecognizerDelegate` PARTAGÉ à tous
/// les reconnaisseurs posés sur `TiledMapRepresentable` — celui du placement
/// et celui de la désignation du départ de tournée compris. `gestureRecognizerShouldBegin`
/// ne doit répondre pour le placement QUE si l'appelant est un des
/// reconnaisseurs de placement ; tout autre reconnaisseur doit être accepté
/// sans condition, sous peine d'être armé mais totalement inerte.
@MainActor
struct MapGestureDelegateTests {
    /// Avant la garde d'identité, ce délégué partagé refusait tout
    /// reconnaisseur dès que `placementContentPoint` était nil — donc le tap
    /// du parcours ne franchissait jamais `.possible`. Armé et inerte, sans
    /// erreur ni test pour le dire.
    @Test func gestureRecognizerShouldBeginAcceptsAForeignRecognizer() {
        let coordinator = TiledMapRepresentable.Coordinator(
            viewport: .constant(MapViewport()),
            onLongPress: { _ in }
        )
        #expect(coordinator.gestureRecognizerShouldBegin(UITapGestureRecognizer()) == true)
    }
}
