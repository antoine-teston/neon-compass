import SwiftUI

/// Une puce de filtre, telle que l'Actu et les Codes l'emploient.
///
/// Extraite de `FeedFilterBar` quand l'écran Codes a eu besoin de la même
/// rangée. Un second exemplaire aurait divergé — c'est exactement ce qui était
/// arrivé à `MapGame` et `NewsGame`, deux énumérations jumelles dont l'une
/// prétendait réutiliser le vocabulaire de l'autre.
struct FilterChip: View {
    let title: Text
    var symbol: String?
    let isSelected: Bool

    /// Si cette puce POSE un filtre. Les puces « tout » n'en posent pas : elles
    /// marquent l'absence de restriction, et les allumer en cyan revenait à
    /// peindre en couleur d'accent l'état où il ne se passe rien. Vu à l'écran,
    /// ça faisait deux capsules cyan permanentes au-dessus d'un compte à rebours
    /// qui en porte déjà trois, et surtout ça vidait le cyan de son sens — la
    /// couleur ne disait plus « un filtre est posé », puisqu'elle était là par
    /// défaut.
    var isRestriction: Bool = true

    /// Fait respirer la puce. Réservé à celle qui nomme le jeu à venir.
    var breathes: Bool = false

    let accessibilityLabel: Text
    let action: () -> Void

    var body: some View {
        Button {
            guard !isSelected else { return }
            // SURTOUT PAS de `withAnimation` ici, et c'est mesuré.
            //
            // L'action remplace tout le contenu de la liste filtrée. Enveloppée
            // dans une animation, SwiftUI animait l'apparition et la disparition
            // de dizaines de cartes portant chacune un `.glassEffect()` : douze
            // images perdues et jusqu'à 127 ms de blocage par tap, contre zéro à
            // une image sans elle. L'animation qu'on veut est celle de la PUCE,
            // et elle est posée en `.animation(_:value:)` sur la rangée.
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                title
            }
            .font(NCTypography.cardMeta)
            .foregroundStyle(textStyle)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Le verre TEINTÉ plutôt qu'une capsule pleine posée derrière lui :
            // `CompactTabBar` marque déjà sa sélection ainsi, et empiler un fond
            // opaque sous du verre revient à payer le verre sans le voir.
            .glassEffect(glass, in: .capsule)
            .breathingHighlight(breathes)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Trois états et non deux : cyan pour un filtre posé, verre blanchi pour la
    /// puce « tout » quand elle est active, verre nu pour le reste.
    private var glass: Glass {
        guard isSelected else { return .regular.interactive() }
        return .regular
            .tint(isRestriction ? NCColor.neonCyan : .white.opacity(0.22))
            .interactive()
    }

    private var textStyle: Color {
        guard isSelected else { return .white.opacity(0.8) }
        // Le cyan est assez clair pour exiger un texte sombre ; le verre
        // blanchi, lui, reste sombre et garde son texte en blanc.
        return isRestriction ? NCColor.nightSky : .white
    }
}

/// La rangée qui porte les puces : défilement horizontal, marges internes, et
/// l'animation de sélection ciblée.
///
/// Une rangée qui défile plutôt qu'une grille ou un menu : plusieurs lignes de
/// puces mangeraient une hauteur que ces écrans n'ont pas — barre haute et barre
/// d'onglets en prennent déjà cent vingt points — et un menu coûterait deux
/// gestes là où filtrer doit en coûter un.
struct FilterChipRow<Content: View>: View {
    /// Ce qui, en changeant, mérite d'animer les puces. L'animation est posée
    /// ICI et non sur l'action : elle ne doit toucher que la rangée, jamais la
    /// liste que le filtre remplace.
    let animationTrigger: AnyHashable

    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    content
                }
                // Les marges de la liste sont posées par ses éléments ; la
                // rangée reprend les siennes à l'intérieur du défilement pour
                // que les puces glissent bord à bord au lieu de s'arrêter à
                // seize points du vide.
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
        .animation(.snappy, value: animationTrigger)
    }
}

/// La COLONNE qui porte les puces, pour un panneau qui se déplie.
///
/// C'est la géométrie du panneau de filtres de la carte : les puces s'empilent
/// alignées à droite, sous le bouton qui les a ouvertes, et l'alignement les fait
/// pointer vers lui. La rangée ci-dessus reste le bon choix quand les puces sont
/// là en permanence — elle ne coûte qu'une ligne ; la colonne, elle, prend la
/// hauteur de six puces, ce qu'on ne consent que pour un panneau transitoire.
///
/// Pas de `GlassEffectContainer` ici : celui qui compte englobe AUSSI le bouton
/// qui déplie, sans quoi les puces ne peuvent pas se fondre avec lui. Il est donc
/// posé par l'appelant, un cran plus haut.
struct FilterChipColumn<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Le séparateur entre deux groupes de puces.
///
/// Il coupe EN TRAVERS de l'axe où les puces s'enchaînent : un trait vertical
/// dans une rangée, horizontal dans une colonne. Le même trait dans les deux
/// sens ne séparerait rien dans l'un des deux.
struct FilterChipDivider: View {
    /// L'axe le long duquel les PUCES s'enchaînent, pas celui du trait — le
    /// trait, lui, est toujours perpendiculaire.
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(
                width: axis == .horizontal ? 1 : 40,
                height: axis == .horizontal ? 20 : 1
            )
            .padding(axis == .horizontal ? .horizontal : .vertical, 2)
            .accessibilityHidden(true)
    }
}
