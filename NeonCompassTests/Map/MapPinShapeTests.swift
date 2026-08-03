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
