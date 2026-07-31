import Testing
import CoreGraphics
@testable import NeonCompass

/// L'optimisation du chemin de zoom repose entièrement sur une prémisse : ce
/// que le contenu de carte retient du zoom est une fonction EN ESCALIER, donc
/// constante sur de larges plages. Si elle cessait d'être vraie, SwiftUI
/// réévaluerait le corps à chaque frame de pincement et reconstruirait toutes
/// les pastilles — exactement ce que ces valeurs dérivées existent pour éviter.
struct MapRenderStateTests {
    private static let contentSize: CGFloat = 2048

    private func state(_ zoom: CGFloat) -> MapRenderState {
        MapRenderState(zoomScale: zoom, contentSize: Self.contentSize)
    }

    /// Le cas qui motive tout : au dézoom, la contre-échelle est plafonnée à 1
    /// et la grille est quantifiée. Deux zooms voisins sous le seuil neutre
    /// donnent donc le MÊME état, et la vue ne bouge pas.
    @Test func zoomingOutWithinOneQuantizationStepLeavesTheStateUntouched() {
        #expect(state(0.66) == state(0.70))
        #expect(state(0.66).pinScale == 1, "la contre-échelle est plafonnée à 1")
        #expect(state(0.70).pinScale == 1)
    }

    /// Toute la plage de dézoom partage la même contre-échelle : seul le palier
    /// de quantification peut encore différencier deux états.
    @Test func theCounterScaleIsClampedAcrossTheWholeZoomOutRange() {
        for zoom in stride(from: 0.3, through: 1.0, by: 0.05) {
            #expect(state(CGFloat(zoom)).pinScale == 1, "zoom \(zoom)")
        }
    }

    /// Franchir un palier de demi-octave doit bel et bien produire un état
    /// différent — sinon les pastilles ne se délieraient jamais.
    @Test func crossingAQuantizationStepChangesTheState() {
        let below = state(0.70)
        let above = state(1.60)
        #expect(below != above)
        #expect(below.clusterShape != above.clusterShape)
    }

    /// Au-delà du zoom neutre la contre-échelle varie réellement : c'est du
    /// travail légitime, pas du gaspillage.
    @Test func aboveNeutralZoomTheCounterScaleTracksTheZoom() {
        #expect(state(2.0).pinScale < state(1.5).pinScale)
        #expect(state(1.5).pinScale < 1)
    }

    /// Le seuil de désagrégation se lit dans l'état, et pas seulement dans le
    /// palier : c'est ce qui empêche de confondre les zooms 1,9 et 2,0.
    @Test func theDisaggregationThresholdShowsUpInTheState() {
        #expect(state(1.9).clusterShape.disaggregated == false)
        #expect(state(2.0).clusterShape.disaggregated == true)
        #expect(state(1.9) != state(2.0))
    }
}
