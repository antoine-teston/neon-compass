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

    /// Les zones de frappe des épingles personnelles doivent entrer dans le MÊME
    /// balayage que les groupes éditoriaux.
    ///
    /// Le commentaire d'origine de `editorialHitSides` justifiait de les exclure
    /// par le fait qu'elles « ne se tapent pas du tout ». Ce n'est plus vrai : une
    /// épingle posée à côté d'un lieu lui volerait ses taps avec ses 44 pt.
    /// L'argument de non-recouvrement est géométrique, il ne connaît pas les
    /// familles — ce test verrouille le contrat sur lequel repose le balayage
    /// unique.
    @Test func aPersonalPinDoesNotStealItsNeighboursTaps() {
        // Deux points distants de 30 pt de contenu, avec un plafond de 44 :
        // aucun des deux ne doit garder le plafond.
        let positions = [CGPoint(x: 100, y: 100), CGPoint(x: 130, y: 100)]
        let sides = MapPinMetrics.hitSides(for: positions, cap: 44)
        #expect(sides.count == 2)
        for side in sides {
            #expect(side <= 30.5, "zone de \(side) pt pour des voisins à 30 pt : elles se recouvrent")
        }
    }

    /// Et la réciproque : isolées, elles gardent leur pleine cible.
    @Test func anIsolatedPinKeepsTheFullTarget() {
        let positions = [CGPoint(x: 100, y: 100), CGPoint(x: 600, y: 600)]
        let sides = MapPinMetrics.hitSides(for: positions, cap: 44)
        #expect(sides.allSatisfy { abs($0 - 44) < 0.001 })
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

    /// Le plafond ne DÉPASSE jamais 44 pt à l'écran.
    ///
    /// C'est la correction du premier jet, qui quantifiait dans l'autre sens et
    /// laissait la cible monter à 62 pt : on attrapait régulièrement la pastille
    /// voisine. La taille écran vaut `côté × pinScale × zoomScale`, où `pinScale`
    /// est la contre-échelle plafonnée à 1 du moteur de carte.
    @Test func theCapNeverExceedsFortyFourPointsOnScreen() {
        for zoom in scales {
            let side = MapPinMetrics.hitSide(
                forEffectiveScale: MapPinMetrics.quantizedEffectiveScale(zoomScale: zoom)
            )
            let onScreen = side * min(1 / zoom, 1) * zoom
            #expect(
                onScreen <= MapPinMetrics.minimumTouchSide + 0.001,
                "au zoom \(zoom) la cible monte à \(onScreen) pt"
            )
        }
    }

    /// Le pendant : la quantification ne doit pas la faire fondre non plus. Le pire
    /// cas d'un pas de demi-octave est 44/√2 ≈ 31 pt, soit trois fois le dessin nu.
    @Test func theCapStaysComfortablyAboveTheDrawnPin() {
        for zoom in scales {
            let side = MapPinMetrics.hitSide(
                forEffectiveScale: MapPinMetrics.quantizedEffectiveScale(zoomScale: zoom)
            )
            let onScreen = side * min(1 / zoom, 1) * zoom
            #expect(onScreen >= 30, "au zoom \(zoom) : \(onScreen) pt")
        }
    }

    @Test func theQuantizedScaleNeverFallsBelowTheRealOne() {
        for zoom in scales {
            let quantized = MapPinMetrics.quantizedEffectiveScale(zoomScale: zoom)
            #expect(quantized >= min(1, zoom) - 0.001, "au zoom \(zoom) : \(quantized)")
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

/// Le non-chevauchement des zones de frappe.
///
/// C'est l'invariant qui remplace une hypothèse fausse : « l'agrégation garantit
/// 44 pt d'écart à l'écran entre deux pastilles ». La grille garantit seulement
/// que deux points tombent dans des CELLULES distinctes — deux centroïdes de part
/// et d'autre d'une frontière peuvent être collés — et au-delà du seuil de
/// désagrégation il n'y a plus de grille. Des zones fixes de 44 pt se recouvraient
/// donc, et le tap partait sur la voisine.
struct MapPinHitSpacingTests {
    private let cap: CGFloat = 100

    /// L'invariant central : deux zones ne se recouvrent jamais. Deux disques de
    /// diamètres `d₁` et `d₂` centrés à distance `d` sont disjoints dès que
    /// `d₁/2 + d₂/2 ≤ d`.
    @Test func noTwoHitAreasEverOverlap() {
        // Un semis volontairement méchant : des paires très proches, des points
        // confondus en abscisse, et des isolés.
        let positions: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 8, y: 0),          // collées
            CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 340),  // même abscisse
            CGPoint(x: 1000, y: 50),                            // isolée
            CGPoint(x: 1000, y: 95), CGPoint(x: 1030, y: 120),
            CGPoint(x: 40, y: 500), CGPoint(x: 41, y: 501),
        ]
        let sides = MapPinMetrics.hitSides(for: positions, cap: cap)
        for i in positions.indices {
            for j in positions.indices where j > i {
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let distance = (dx * dx + dy * dy).squareRoot()
                // Le plancher du dessin peut encore faire se toucher deux pastilles
                // quasi confondues — elles se recouvrent déjà à l'œil, et rien ne
                // pourrait les départager. On n'exige donc rien sous ce seuil.
                guard distance >= MapPinMetrics.drawnSide else { continue }
                #expect(
                    sides[i] / 2 + sides[j] / 2 <= distance + 0.001,
                    "les zones \(i) et \(j) se recouvrent : \(sides[i]) et \(sides[j]) pour \(distance) d'écart"
                )
            }
        }
    }

    /// Une pastille isolée doit garder toute la cible : borner à la voisine ne doit
    /// pas rétrécir ce qui n'avait pas besoin de l'être.
    @Test func anIsolatedPinKeepsTheFullCap() {
        let sides = MapPinMetrics.hitSides(
            for: [CGPoint(x: 0, y: 0), CGPoint(x: 900, y: 900)], cap: cap
        )
        #expect(sides == [cap, cap])
    }

    /// Et une seule pastille n'a personne à ménager.
    @Test func aLonePinKeepsTheFullCap() {
        #expect(MapPinMetrics.hitSides(for: [CGPoint(x: 5, y: 5)], cap: cap) == [cap])
        #expect(MapPinMetrics.hitSides(for: [], cap: cap).isEmpty)
    }

    /// Jamais sous le dessin : une zone plus petite que la pastille visible serait
    /// un piège, pas une optimisation.
    @Test func theHitAreaNeverShrinksBelowTheDrawnPin() {
        let sides = MapPinMetrics.hitSides(
            for: [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 4, y: 0)], cap: cap
        )
        #expect(sides.allSatisfy { $0 >= MapPinMetrics.drawnSide })
    }

    /// L'ordre du résultat suit celui des positions reçues — le moteur s'en sert
    /// pour l'apparier aux identifiants de groupe.
    @Test func theResultKeepsTheInputOrder() {
        let positions = [CGPoint(x: 500, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0)]
        let sides = MapPinMetrics.hitSides(for: positions, cap: cap)
        // La première est isolée, les deux suivantes sont à 30 l'une de l'autre.
        #expect(sides[0] == cap)
        #expect(sides[1] == 30)
        #expect(sides[2] == 30)
    }
}
