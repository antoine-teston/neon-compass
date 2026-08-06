import SwiftUI

/// Les épingles de la carte, sorties du moteur de carte.
///
/// Elles vivent dans leurs propres types pour DEUX raisons, et la seconde est
/// une affaire de vitesse autant que de rangement :
///
/// 1. `MapScrollView` portait le langage visuel de cinq familles d'épingles en
///    plus du moteur de zoom. Deux sujets sans rapport dans un fichier de 600
///    lignes.
/// 2. Surtout : ce sont des vues `Equatable`. Le moteur repousse tout son
///    contenu d'un bloc dès qu'une donnée change (voir `ContentToken`), et
///    SwiftUI reconstruisait alors CHAQUE pastille visible — y compris celles
///    qui n'avaient pas bougé. Combinée à `.equatable()` au site d'appel,
///    l'égalité laisse SwiftUI sauter le corps des épingles inchangées.
///
/// Deux conséquences de forme, qui expliquent pourquoi ces types ne portent
/// AUCUNE action :
///
/// - Le geste reste au site d'appel, dans un `Button` qui les enveloppe. Une
///   fermeture n'est ni comparable ni `Sendable` : en concurrence stricte, sa
///   seule présence dans la vue fait échouer la conformité (« conformance to
///   Equatable crosses into main actor-isolated code »). Et même acceptée, elle
///   l'aurait vidée de son sens, puisqu'une fermeture fraîche est allouée à
///   chaque reconstruction.
/// - Ce qui dépend du zoom (contre-échelle, position) reste dehors aussi : le
///   glisser ici ferait varier la valeur de la vue à chaque frame de pincement et
///   annulerait tout le bénéfice.

// MARK: - Mesures

/// Ce que les épingles mesurent, dessin et zone de frappe séparés.
enum MapPinMetrics {
    /// Côté du dessin d'une pastille de POI, en coordonnées de contenu.
    static let drawnSide: CGFloat = 24

    /// Minimum du HIG pour une cible tactile.
    static let minimumTouchSide: CGFloat = 44

    /// Côté de la zone de frappe, pour que la cible fasse `minimumTouchSide` à
    /// l'écran quand le contenu est affiché à `effectiveScale`.
    ///
    /// Jamais plus petite que le dessin : une zone de frappe qui rognerait la
    /// pastille visible serait un piège, pas une optimisation.
    static func hitSide(forEffectiveScale effectiveScale: CGFloat) -> CGFloat {
        max(drawnSide, minimumTouchSide / max(effectiveScale, 0.01))
    }

    /// Facteur par lequel le contenu est réellement réduit à l'écran, quantifié
    /// par paliers de demi-octave — pour que `MapRenderState` reste une fonction
    /// EN ESCALIER du zoom et ne se réévalue pas à chaque frame de pincement.
    ///
    /// Quantifié vers le HAUT, donc la cible ne DÉPASSE jamais les 44 pt : c'est le
    /// sens de l'arrondi qui a été corrigé après essai à la main. Vers le bas, elle
    /// montait jusqu'à 62 pt à l'écran, et on attrapait régulièrement la pastille
    /// voisine. Le prix de ce sens-ci est une cible qui descend au pire à 44/√2 ≈
    /// 31 pt, ce qui reste trois fois le dessin nu.
    ///
    /// Plafonné à 1 : au-delà du zoom neutre la contre-échelle des épingles annule
    /// l'agrandissement, donc leur taille écran ne dépend plus du zoom.
    static func quantizedEffectiveScale(zoomScale: CGFloat) -> CGFloat {
        guard zoomScale > 0, zoomScale.isFinite else { return 1 }
        let level = (log2(Double(zoomScale)) * 2).rounded(.up)
        return min(1, CGFloat(pow(2.0, level / 2)))
    }

    /// Côtés des zones de frappe d'un ensemble de pastilles, garantis SANS
    /// CHEVAUCHEMENT.
    ///
    /// C'est ce qui remplace l'hypothèse fausse sur laquelle reposait la première
    /// version : « l'agrégation garantit 44 pt d'écart à l'écran ». Elle ne le
    /// garantit pas. La grille assure que deux points tombent dans des CELLULES
    /// distinctes, pas qu'ils soient éloignés — deux centroïdes de part et d'autre
    /// d'une frontière peuvent être collés — et au-delà du seuil de désagrégation
    /// il n'y a plus de grille du tout. Résultat : des zones de 44 pt qui se
    /// recouvraient, et un tap qui atterrissait sur la voisine.
    ///
    /// Chaque zone est donc bornée par la distance à sa plus proche voisine. Deux
    /// zones de diamètres `d₁` et `d₂` séparées de `d ≥ max(d₁, d₂)` ne se
    /// recouvrent pas, puisque `d₁/2 + d₂/2 ≤ d`. La forme de frappe doit être
    /// RONDE pour que cet argument tienne : les coins d'un carré de côté `d`
    /// dépassent, eux, jusqu'à `d/√2` du centre.
    ///
    /// - Parameters:
    ///   - positions: positions en coordonnées de contenu.
    ///   - cap: côté maximal, c'est-à-dire ce que valent 44 pt d'écran ici.
    /// - Returns: un côté par position, dans le même ordre.
    static func hitSides(for positions: [CGPoint], cap: CGFloat) -> [CGFloat] {
        guard positions.count > 1 else { return Array(repeating: cap, count: positions.count) }
        // Balayage par abscisse croissante : au-delà de `cap` en x, tout le reste
        // est plus loin encore, donc on s'arrête. Chaque pastille ne compare donc
        // qu'avec la poignée de voisines qui pourraient la gêner, et non avec les
        // deux cents autres.
        let order = positions.indices.sorted { positions[$0].x < positions[$1].x }
        var nearest = [CGFloat](repeating: cap, count: positions.count)
        for a in order.indices {
            let i = order[a]
            var b = a + 1
            while b < order.count {
                let j = order[b]
                let dx = positions[j].x - positions[i].x
                if dx >= cap { break }
                let dy = positions[j].y - positions[i].y
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < nearest[i] { nearest[i] = distance }
                if distance < nearest[j] { nearest[j] = distance }
                b += 1
            }
        }
        // Jamais sous le dessin : une zone qui rognerait la pastille visible serait
        // un piège. Deux pastilles posées au même endroit se recouvrent donc encore
        // — mais elles se recouvrent déjà à l'œil, et rien ne peut les départager.
        return positions.indices.map { max(drawnSide, nearest[$0]) }
    }
}

extension View {
    /// Élargit la zone de frappe d'une épingle sans toucher à son dessin.
    ///
    /// À poser DANS la contre-échelle du zoom et non autour : le côté reçu est déjà
    /// exprimé dans l'espace de l'épingle (voir `MapPinMetrics.hitSides`).
    ///
    /// `minWidth`/`minHeight` et non `width`/`height` : une pastille de groupe à
    /// trois chiffres est plus large que haute, et un cadre fixe lui aurait rendu
    /// ses extrémités intouchables.
    ///
    /// La forme est une CAPSULE, jamais un rectangle : sur un cadre carré c'est un
    /// disque, et c'est ce qui rend vraie la garantie de non-chevauchement de
    /// `hitSides` — les coins d'un carré dépassent, eux, de 41 %. Sans
    /// `contentShape`, enfin, seul le dessin intercepterait et le cadre élargi ne
    /// servirait à rien.
    func pinHitArea(side: CGFloat) -> some View {
        frame(minWidth: side, minHeight: side)
            .contentShape(.capsule)
    }
}

// MARK: - Silhouettes

/// Goutte — la silhouette universelle du « j'ai posé ça ici ».
///
/// C'est ce qui sépare les épingles POSÉES PAR QUELQU'UN (les siennes, celles de
/// la communauté) des points éditoriaux, qui restent des disques. La distinction
/// ne pouvait pas passer par la couleur : les six teintes de catégorie sont déjà
/// prises, et l'orange des épingles personnelles était EXACTEMENT celui de la
/// catégorie « véhicule ». Elle passe donc par la forme, ce qui est de toute
/// façon la règle de cette carte — le symbole porte l'information, la couleur la
/// renforce.
///
/// Un seul contour continu, et non un cercle posé sur un triangle : la seconde
/// solution se remplit correctement mais laisse voir ses coutures dès qu'on la
/// CERCLE, et l'anneau néon est tout l'intérêt.
struct MapPinTeardrop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        let distance = tip.y - center.y
        // Cadre trop court pour une pointe : on retombe sur le disque plutôt que
        // de sortir une forme dégénérée.
        guard distance > radius else {
            path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.width))
            return path
        }
        // Point où le cercle rejoint les flancs. La tangente y est commune aux
        // deux, donc le raccord ne fait aucune cassure — c'est ce qui distingue
        // une goutte d'un cercle à qui on a collé un cône.
        let phi = Angle.radians(acos(radius / distance))
        path.move(to: tip)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(90) + phi,
            endAngle: .degrees(90) - phi,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Point d'intérêt éditorial

/// Pastille d'un POI publié : cœur neutre, anneau néon en couleur de catégorie,
/// glyphe de la même couleur.
struct POIPinView: View, Equatable {
    let category: POICategory
    let style: MapStyle
    let isFound: Bool
    let accessibilityTitle: String

    private var tint: Color { POIPinPalette.color(for: category, style: style) }

    var body: some View {
        // AUCUNE animation ici, et c'est une décision mesurée — voir l'en-tête du
        // fichier. Le changement est instantané, ce qui est l'inverse d'une
        // lenteur : le retour animé vit dans la fiche, où il ne coûte rien.
        return Image(systemName: isFound ? "checkmark" : POIPinPalette.symbol(for: category))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: MapPinMetrics.drawnSide, height: MapPinMetrics.drawnSide)
            .background(Circle().fill(POIPinPalette.core(for: style).opacity(POIPinPalette.coreOpacity(found: isFound))))
            .overlay(
                Circle().strokeBorder(
                    tint.opacity(isFound ? 0.6 : 1),
                    lineWidth: POIPinPalette.ringWidth(found: isFound)
                )
            )
            .shadow(
                color: tint.opacity(0.55),
                radius: POIPinPalette.glowRadius(for: style, found: isFound)
            )
            .accessibilityLabel(Text(accessibilityTitle))
            .accessibilityValue(isFound ? Text("poi.detail.found") : Text(verbatim: ""))
    }
}

// MARK: - Pastille d'agrégation

/// Groupe de points. Un tap zoome dessus plutôt que d'ouvrir une fiche : c'est le
/// geste attendu, et c'est ce qui délie le groupe.
struct MapClusterBubbleView: View, Equatable {
    /// Ce que le groupe agrège — les deux familles ne se rendent pas pareil.
    enum Family: Equatable {
        /// POI éditoriaux : la couleur vient de la catégorie majoritaire.
        case editorial
        /// Propositions de joueurs : glyphe d'épingle et teinte communautaire,
        /// pour qu'on ne confonde pas « douze lieux du guide » et « douze
        /// propositions de joueurs ».
        case community
    }

    let count: Int
    /// Membres déjà trouvés. Nourrit l'arc de progression — sans lui, au dézoom,
    /// cocher un lieu ne produisait AUCUN retour visible : un groupe de douze
    /// entièrement trouvé se présentait comme un groupe où rien ne l'était.
    let foundCount: Int
    let category: POICategory
    let style: MapStyle
    let family: Family

    /// Le poids suit le NOMBRE, sur trois paliers.
    ///
    /// Toutes les pastilles avaient la même taille : un groupe de 34 et un
    /// groupe de 2 se présentaient identiquement, ce qui privait la carte de sa
    /// seule hiérarchie possible au dézoom. Trois paliers et pas un continuum —
    /// une taille qui suivrait le compte exact ferait respirer les pastilles à
    /// chaque recomposition de groupe.
    private var weight: (diameter: CGFloat, ring: CGFloat, numeral: CGFloat) {
        switch count {
        case ..<10: (28, 1.5, 13)
        case ..<50: (33, 2, 15)
        default: (38, 2.5, 16)
        }
    }

    private var tint: Color {
        switch family {
        case .editorial: POIPinPalette.color(for: category, style: style)
        case .community: NCColor.sunsetMagenta
        }
    }

    /// Part de membres qui RESTENT à trouver. C'est elle qu'on dessine en pleine
    /// lumière, pas l'inverse : un groupe intact garde donc exactement l'anneau
    /// qu'il avait, et il s'éteint à mesure qu'on le complète — même sémantique
    /// que les épingles, où le trouvé est plus léger que le reste à faire.
    private var remainingFraction: CGFloat {
        guard count > 0 else { return 1 }
        return CGFloat(max(0, count - foundCount)) / CGFloat(count)
    }

    var body: some View {
        let weight = weight
        let remaining = remainingFraction
        // La capsule est INCRUSTÉE d'un demi-trait pour que les deux passages se
        // superposent exactement : `strokeBorder` rentre de lui-même, `stroke` non,
        // et les mêler décalait l'arc de la moitié de son épaisseur.
        let ring = Capsule().inset(by: weight.ring / 2)
        return HStack(spacing: 3) {
            if family == .community {
                Image(systemName: "mappin")
                    .font(.system(size: weight.numeral - 3, weight: .bold))
            }
            Text(count, format: .number)
                .font(.system(size: weight.numeral, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint.opacity(remaining == 0 ? 0.6 : 1))
        .padding(.horizontal, 8)
        .frame(minWidth: weight.diameter, minHeight: weight.diameter)
        .background(Capsule().fill(POIPinPalette.core(for: style).opacity(POIPinPalette.coreOpacity(found: remaining == 0))))
        // Le fait, en sourdine, sur tout le tour.
        .overlay(ring.stroke(tint.opacity(0.3), lineWidth: weight.ring))
        // Ce qui reste, par-dessus. Un groupe intact est donc plein et lumineux
        // comme avant ; il n'y a d'arc que là où il y a du progrès.
        .overlay(ring.trim(from: 0, to: remaining).stroke(tint, lineWidth: weight.ring))
        // Le halo s'éteint avec le reste à faire — c'est ce qui tient la consigne
        // du CLAUDE.md (« glow on at most three accents per screen ») à mesure que
        // la carte se complète.
        .shadow(color: tint.opacity(0.45 * remaining), radius: POIPinPalette.glowRadius(for: style))
        .accessibilityLabel(Text("map.cluster.accessibility \(count)"))
        .accessibilityValue(foundCount > 0 ? Text("map.cluster.foundAccessibility \(foundCount)") : Text(verbatim: ""))
    }
}

// MARK: - Épingles posées par quelqu'un

/// Épingle en goutte, pointe sur le lieu. Sert aux deux familles d'épingles
/// posées à la main : les siennes et celles de la communauté.
struct DroppedPinView: View, Equatable {
    let symbol: String
    let tint: Color
    let style: MapStyle
    /// Une épingle faite s'éteint EXACTEMENT comme un lieu trouvé et comme un
    /// groupe complété — mêmes fonctions de palette, donc même sémantique. Le
    /// joueur n'a pas un second langage visuel à apprendre, et le halo qui
    /// s'éteint tient la consigne du CLAUDE.md (« glow on at most three accents
    /// per screen ») à mesure que le carnet se remplit.
    ///
    /// Valeur par défaut : les propositions communautaires n'ont pas d'état
    /// « fait » — elles ne sont pas dans la progression — et gardent donc la
    /// goutte pleine sans rien changer à leur site d'appel.
    var isDone: Bool = false
    let accessibilityTitle: String

    /// Largeur de la tête. La hauteur totale en découle — proportion fixe, pour
    /// que la goutte reste une goutte à tous les paliers de contre-échelle.
    static let headWidth: CGFloat = 22
    static var height: CGFloat { headWidth * 1.36 }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint.opacity(isDone ? 0.6 : 1))
            .frame(width: Self.headWidth, height: Self.headWidth)
            // Le glyphe vit dans la TÊTE, pas au centre de la goutte : centré sur
            // la forme entière il chevaucherait la pointe.
            .frame(width: Self.headWidth, height: Self.height, alignment: .top)
            .background(MapPinTeardrop().fill(POIPinPalette.core(for: style).opacity(POIPinPalette.coreOpacity(found: isDone))))
            .overlay(MapPinTeardrop().stroke(tint.opacity(isDone ? 0.6 : 1), lineWidth: POIPinPalette.ringWidth(found: isDone)))
            .shadow(color: tint.opacity(0.5), radius: POIPinPalette.glowRadius(for: style, found: isDone))
            // La POINTE désigne le lieu, pas le centre de la forme. `position`
            // pose les centres : sans ce décalage, chaque épingle indiquerait un
            // point situé une demi-hauteur trop bas. Il est posé DEDANS pour
            // être mis à l'échelle avec le reste par la contre-échelle du zoom.
            .offset(y: -Self.height / 2)
            .accessibilityLabel(Text(accessibilityTitle))
            .accessibilityValue(isDone ? Text("map.pins.card.done") : Text(verbatim: ""))
    }
}
