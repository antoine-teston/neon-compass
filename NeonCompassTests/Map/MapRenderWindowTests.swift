import CoreGraphics
import Testing
@testable import NeonCompass

/// La fenêtre de rendu décide quelles pastilles EXISTENT. Une erreur ici ne se
/// paie pas en millisecondes mais en points de carte absents — bien pire que la
/// lenteur qu'elle corrige. Ces tests portent donc d'abord sur ce qu'elle ne
/// doit jamais retrancher, ensuite sur la cadence à laquelle elle change.
struct MapRenderWindowTests {
    private static let contentSize: CGFloat = 2048

    /// Deux géométries réelles, mesurées sur les simulateurs de référence.
    private enum Device {
        static let phoneBounds = CGSize(width: 393, height: 852)
        /// Échelle de repos sur iPhone : la carte remplit les deux axes.
        static let phoneCoverZoom: CGFloat = 852 / 2048
    }

    private func window(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, zoomScale: CGFloat = 1
    ) -> MapRenderWindow {
        MapRenderWindow(
            visibleContentRect: CGRect(x: x, y: y, width: width, height: height),
            contentSize: Self.contentSize,
            zoomScale: zoomScale
        )
    }

    /// La fenêtre telle que la produirait une vue de défilement réelle.
    private func window(forScrollOffset offset: CGFloat, zoomScale: CGFloat) -> MapRenderWindow {
        MapRenderWindow(
            visibleContentRect: MapGeometry.visibleContentRect(
                bounds: Device.phoneBounds,
                contentOffset: CGPoint(x: offset, y: 0),
                zoomScale: zoomScale
            ),
            contentSize: Self.contentSize,
            zoomScale: zoomScale
        )
    }

    private func point(_ x: Double, _ y: Double) -> NormalizedPoint {
        NormalizedPoint(x: x, y: y)
    }

    // MARK: - Ce qui doit rester affiché

    @Test func aPointInsideTheVisibleRectIsRendered() {
        let visible = window(x: 512, y: 512, width: 256, height: 256, zoomScale: 2)
        #expect(visible.contains(point(0.28, 0.28)))
        #expect(visible.contains(point(0.35, 0.35)))
    }

    /// Le coin extrême de la carte, que le découpage ne doit jamais rogner.
    @Test func theFarCornerOfTheMapIsNeverDropped() {
        let everything = window(x: 0, y: 0, width: Self.contentSize, height: Self.contentSize)
        #expect(everything.contains(point(1.0, 1.0)))
        #expect(everything.contains(point(0.0, 0.0)))
        #expect(MapRenderWindow.whole.contains(point(1.0, 1.0)))
    }

    /// La marge empêche une pastille de surgir pile au bord de l'écran au
    /// moment où elle y entre.
    @Test func aPointJustOutsideTheVisibleRectIsStillRendered() {
        let zoom: CGFloat = 2
        let tile = Double(MapRenderWindow.tileScreenSize / zoom)
        let visible = window(x: 800, y: 800, width: 200, height: 200, zoomScale: zoom)
        // Une demi-tuile au-delà du bord gauche : hors écran, mais dans la marge.
        #expect(visible.contains(point((800 - tile / 2) / Double(Self.contentSize), 900 / Double(Self.contentSize))))
    }

    /// Repli sûr : une géométrie inconnue doit tout afficher, jamais rien.
    @Test func degenerateGeometryFallsBackToTheWholeMap() {
        #expect(window(x: 0, y: 0, width: 0, height: 0) == .whole)
        #expect(MapRenderWindow(visibleContentRect: CGRect(x: 0, y: 0, width: 100, height: 100), contentSize: 0, zoomScale: 1) == .whole)
        #expect(window(x: .nan, y: 0, width: 100, height: 100) == .whole)
        #expect(window(x: 0, y: 0, width: 100, height: 100, zoomScale: 0) == .whole)
        #expect(window(x: 0, y: 0, width: 100, height: 100, zoomScale: .nan) == .whole)
    }

    /// Les encarts de centrage rendent `contentOffset` négatif : la fenêtre
    /// déborde alors du contenu et doit se borner sans rien perdre du bord.
    @Test func aRectStartingBeforeTheMapStillRendersTheTopLeft() {
        let overhanging = window(x: -400, y: -400, width: 600, height: 600, zoomScale: 2)
        #expect(overhanging.contains(point(0, 0)))
        #expect(overhanging.minX == 0)
        #expect(overhanging.minY == 0)
    }

    // MARK: - Ce qui doit être retranché

    @Test func aPointFarOutsideTheVisibleRectIsDropped() {
        let visible = window(x: 0, y: 0, width: 128, height: 128, zoomScale: 2.5)
        #expect(!visible.contains(point(0.9, 0.9)))
        #expect(!visible.contains(point(0.5, 0.5)))
    }

    /// Le gain attendu, en clair : au zoom maximal la fenêtre ne garde qu'une
    /// petite fraction d'une distribution uniforme.
    @Test func aTightWindowKeepsOnlyAFractionOfAUniformSpread() {
        let visible = window(forScrollOffset: 2000, zoomScale: 2.5)
        let spread = stride(from: 0.02, through: 0.98, by: 0.04).flatMap { x in
            stride(from: 0.02, through: 0.98, by: 0.04).map { point($0, x) }
        }
        let kept = spread.filter(visible.contains).count
        #expect(kept > 0, "une fenêtre valide ne peut pas tout retrancher")
        #expect(Double(kept) / Double(spread.count) < 0.15, "gardé \(kept)/\(spread.count)")
    }

    // MARK: - La cadence de changement, mesurée à l'ÉCRAN

    /// Compte les changements de fenêtre pour un déplacement donné À L'ÉCRAN.
    private func windowChanges(zoomScale: CGFloat, screenTravel: CGFloat) -> Int {
        var changes = 0
        var previous = window(forScrollOffset: 0, zoomScale: zoomScale)
        for step in 1...Int(screenTravel) {
            let current = window(forScrollOffset: CGFloat(step), zoomScale: zoomScale)
            if current != previous {
                changes += 1
                previous = current
            }
        }
        return changes
    }

    /// LE test de non-régression de ce correctif.
    ///
    /// La quantification était exprimée en pixels de CONTENU : une tuile valait
    /// alors 27 pt à l'écran au dézoom maximal contre 160 pt au zoom maximal,
    /// donc six fois plus de franchissements — et chaque franchissement
    /// reconstruit toutes les pastilles. Mesuré sur un panoramique de 300
    /// images : 131 reconstructions contre 45, et 58,6 fps contre 60.
    ///
    /// Exprimée à l'écran, la cadence ne dépend plus du zoom.
    @Test func theWindowChangesAtTheSameScreenCadenceWhateverTheZoom() {
        let travel: CGFloat = 600
        let zoomed = windowChanges(zoomScale: 2.5, screenTravel: travel)
        let midway = windowChanges(zoomScale: 1.2, screenTravel: travel)

        // L'assertion qui porte le correctif : la cadence ne dépend plus du
        // zoom. En quantification par pixels de contenu, ces deux nombres
        // valaient 7 et 15.
        #expect(abs(zoomed - midway) <= 1, "zoom 2,5 : \(zoomed) changements, zoom 1,2 : \(midway)")

        // Et elle reste bornée par la tuile écran — deux changements par tuile
        // parcourue, un par bord de la fenêtre.
        let perTile = Int(travel / MapRenderWindow.tileScreenSize)
        #expect(zoomed <= 2 * perTile + 2, "\(zoomed) changements pour \(travel) pt")
    }

    /// Et au dézoom maximal, la conséquence voulue : la fenêtre couvre alors
    /// tant de carte qu'elle se ramène à l'entier, donc panoramiquer ne la
    /// change PLUS DU TOUT. C'est là que le découpage ne rapportait presque
    /// rien tout en coûtant le plus.
    @Test func panningAtMaximumZoomOutNeverChangesTheWindow() {
        #expect(window(forScrollOffset: 0, zoomScale: Device.phoneCoverZoom) == .whole)
        #expect(windowChanges(zoomScale: Device.phoneCoverZoom, screenTravel: 400) == 0)
    }

    /// La quantification reste une quantification : deux positions dans la même
    /// tuile donnent la même fenêtre.
    @Test func panningWithinOneTileLeavesTheWindowUntouched() {
        let start = window(forScrollOffset: 500, zoomScale: 2.5)
        let nudged = window(forScrollOffset: 505, zoomScale: 2.5)
        #expect(start == nudged)
    }

    /// Mais franchir une tuile doit bel et bien la changer, sinon la fenêtre se
    /// figerait et des pastilles manqueraient.
    @Test func crossingATileBoundaryMovesTheWindow() {
        let zoom: CGFloat = 2.5
        let start = window(forScrollOffset: 0, zoomScale: zoom)
        let moved = window(forScrollOffset: MapRenderWindow.tileScreenSize * 2, zoomScale: zoom)
        #expect(start != moved)
    }
}
