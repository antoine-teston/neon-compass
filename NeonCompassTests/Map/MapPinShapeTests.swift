import SwiftUI
import Testing
@testable import NeonCompass

/// La goutte est construite par trigonométrie, avec un arc dont le SENS de
/// balayage n'est pas déductible à la lecture (`Path` compte ses angles dans un
/// repère à l'axe vertical inversé). Pris à l'envers, l'arc rejoint ses points de
/// tangence par le bas au lieu de passer par le haut : la forme obtenue est un
/// croissant, pas une goutte, et elle se dessine sans la moindre erreur.
///
/// Ces tests portent donc sur ce qu'une forme à l'envers trahirait — son emprise
/// et sa pointe.
struct MapPinShapeTests {
    private let frame = CGRect(x: 0, y: 0, width: 22, height: 30)

    /// Une goutte occupe TOUT le cadre proposé. Le croissant de l'arc inversé
    /// n'atteint jamais le haut du cadre : son emprise est plus courte, ce qui se
    /// voit ici même si les deux formes sont des chemins valides.
    @Test func theTeardropFillsItsFrame() {
        let bounds = MapPinTeardrop().path(in: frame).boundingRect
        #expect(abs(bounds.minY - frame.minY) < 0.5, "la tête n'atteint pas le haut du cadre : arc balayé à l'envers")
        #expect(abs(bounds.maxY - frame.maxY) < 0.5)
        #expect(abs(bounds.width - frame.width) < 0.5)
    }

    /// La pointe est le point qui DÉSIGNE le lieu — c'est sur elle que le décalage
    /// de `DroppedPinView` est calé. Elle doit être en bas, au centre.
    @Test func theTipSitsAtTheBottomCenter() {
        let path = MapPinTeardrop().path(in: frame)
        #expect(path.contains(CGPoint(x: frame.midX, y: frame.maxY - 1)))
        // Et les coins bas, eux, sont DEHORS : une forme qui les contiendrait
        // serait un disque étiré, pas une goutte.
        #expect(!path.contains(CGPoint(x: frame.minX + 1, y: frame.maxY - 1)))
        #expect(!path.contains(CGPoint(x: frame.maxX - 1, y: frame.maxY - 1)))
    }

    /// Cadre trop court pour une pointe : on veut le disque de repli, et non une
    /// forme dégénérée ou un chemin vide.
    @Test func aFrameTooShortForATipFallsBackToADisc() {
        let squat = CGRect(x: 0, y: 0, width: 22, height: 12)
        let bounds = MapPinTeardrop().path(in: squat).boundingRect
        #expect(!bounds.isEmpty)
        #expect(abs(bounds.width - bounds.height) < 0.5, "le repli doit être un disque")
    }
}

/// La zone de frappe des épingles.
///
/// Le dessin d'une pastille fait 24 pt de contenu, et le contenu est réduit par
/// la vue de défilement : au repos l'épingle ne mesurait que ~10 pt à l'écran,
/// moins d'un quart du minimum tactile du HIG. Ces tests portent sur la seule
/// chose qui garantit le contraire — le côté du cadre de frappe.
struct MapPinHitAreaTests {
    /// Échelles de repos réelles, mesurées : ≈0,43 sur iPhone 17, ≈0,67 sur iPad
    /// Pro 13". Plus deux paliers de zoom au-delà du neutre.
    private let scales: [CGFloat] = [0.43, 0.5, 0.67, 0.9, 1, 1.5, 2.5]

    /// L'invariant, et la seule raison d'être de tout ce calcul : à n'importe quel
    /// zoom, la cible mesure au moins 44 pt À L'ÉCRAN.
    ///
    /// La taille écran vaut `côté × pinScale × zoomScale`, où `pinScale` est la
    /// contre-échelle plafonnée à 1 du moteur de carte.
    @Test func theTargetIsNeverSmallerThanFortyFourPointsOnScreen() {
        for zoom in scales {
            let side = MapPinMetrics.hitSide(
                forEffectiveScale: MapPinMetrics.quantizedEffectiveScale(zoomScale: zoom)
            )
            let pinScale = min(1 / zoom, 1)
            let onScreen = side * pinScale * zoom
            #expect(
                onScreen >= MapPinMetrics.minimumTouchSide - 0.001,
                "au zoom \(zoom) la cible ne fait que \(onScreen) pt"
            )
        }
    }

    /// Le pendant : une cible démesurée volerait les taps de ses voisines.
    /// L'agrégation garantissant ~44 pt d'écart à l'écran, on se borne au double.
    @Test func theTargetStaysWithinTwiceTheMinimum() {
        for zoom in scales {
            let side = MapPinMetrics.hitSide(
                forEffectiveScale: MapPinMetrics.quantizedEffectiveScale(zoomScale: zoom)
            )
            let onScreen = side * min(1 / zoom, 1) * zoom
            #expect(onScreen <= MapPinMetrics.minimumTouchSide * 2, "au zoom \(zoom) : \(onScreen) pt")
        }
    }

    /// C'est le piège que la quantification vers le bas évite. Arrondir au plus
    /// proche donnait 0,5 pour un zoom de 0,43, donc une cible de 37,8 pt — sous le
    /// minimum. Le test fige le sens de l'arrondi.
    @Test func theQuantizedScaleNeverExceedsTheRealOne() {
        for zoom in scales {
            let quantized = MapPinMetrics.quantizedEffectiveScale(zoomScale: zoom)
            #expect(quantized <= min(1, zoom) + 0.001, "au zoom \(zoom) : \(quantized)")
        }
    }

    /// Fonction EN ESCALIER, et pas continue : sans ça la valeur changerait à
    /// chaque frame de pincement et ferait réévaluer tout le contenu de la carte —
    /// exactement ce que `MapRenderState` existe pour empêcher.
    @Test func theQuantizedScaleIsAStepFunction() {
        #expect(MapPinMetrics.quantizedEffectiveScale(zoomScale: 0.43)
            == MapPinMetrics.quantizedEffectiveScale(zoomScale: 0.46))
        #expect(MapPinMetrics.quantizedEffectiveScale(zoomScale: 1.2)
            == MapPinMetrics.quantizedEffectiveScale(zoomScale: 2.4))
    }

    /// Un zoom absurde ne doit pas produire une zone de frappe infinie.
    @Test func degenerateZoomFallsBackToTheDrawnSize() {
        #expect(MapPinMetrics.quantizedEffectiveScale(zoomScale: 0) == 1)
        #expect(MapPinMetrics.quantizedEffectiveScale(zoomScale: .infinity) == 1)
        #expect(MapPinMetrics.hitSide(forEffectiveScale: 1) == MapPinMetrics.minimumTouchSide)
    }
}
