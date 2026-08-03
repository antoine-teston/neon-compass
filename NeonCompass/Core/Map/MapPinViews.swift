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
        Image(systemName: isFound ? "checkmark" : POIPinPalette.symbol(for: category))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint)
            // Le glyphe MORPHE vers la coche au lieu d'être remplacé d'un coup :
            // c'est le seul retour visuel du marquage sur la carte, et sans lui
            // l'épingle changeait d'état sans que rien ne bouge à l'écran.
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 24, height: 24)
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
            // Portée par l'épingle et non par l'écran : la carte n'anime rien
            // globalement (elle se repousse d'un bloc), donc c'est ici qu'il faut
            // demander la transition, sur la seule valeur qui la justifie.
            .animation(.snappy(duration: 0.28), value: isFound)
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

    var body: some View {
        let weight = weight
        return HStack(spacing: 3) {
            if family == .community {
                Image(systemName: "mappin")
                    .font(.system(size: weight.numeral - 3, weight: .bold))
            }
            Text(count, format: .number)
                .font(.system(size: weight.numeral, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(minWidth: weight.diameter, minHeight: weight.diameter)
        .background(Capsule().fill(POIPinPalette.core(for: style).opacity(0.82)))
        .overlay(Capsule().strokeBorder(tint, lineWidth: weight.ring))
        .shadow(color: tint.opacity(0.45), radius: POIPinPalette.glowRadius(for: style))
        .accessibilityLabel(Text("map.cluster.accessibility \(count)"))
    }
}

// MARK: - Épingles posées par quelqu'un

/// Épingle en goutte, pointe sur le lieu. Sert aux deux familles d'épingles
/// posées à la main : les siennes et celles de la communauté.
struct DroppedPinView: View, Equatable {
    let symbol: String
    let tint: Color
    let style: MapStyle
    let accessibilityTitle: String

    /// Largeur de la tête. La hauteur totale en découle — proportion fixe, pour
    /// que la goutte reste une goutte à tous les paliers de contre-échelle.
    static let headWidth: CGFloat = 22
    static var height: CGFloat { headWidth * 1.36 }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: Self.headWidth, height: Self.headWidth)
            // Le glyphe vit dans la TÊTE, pas au centre de la goutte : centré sur
            // la forme entière il chevaucherait la pointe.
            .frame(width: Self.headWidth, height: Self.height, alignment: .top)
            .background(MapPinTeardrop().fill(POIPinPalette.core(for: style).opacity(0.86)))
            .overlay(MapPinTeardrop().stroke(tint, lineWidth: 2))
            .shadow(color: tint.opacity(0.5), radius: POIPinPalette.glowRadius(for: style))
            // La POINTE désigne le lieu, pas le centre de la forme. `position`
            // pose les centres : sans ce décalage, chaque épingle indiquerait un
            // point situé une demi-hauteur trop bas. Il est posé DEDANS pour
            // être mis à l'échelle avec le reste par la contre-échelle du zoom.
            .offset(y: -Self.height / 2)
            .accessibilityLabel(Text(accessibilityTitle))
    }
}
