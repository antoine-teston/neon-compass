import SwiftUI

/// Les puces de filtre du fil : le jeu, puis la rubrique.
///
/// Une rangée qui défile plutôt qu'une grille ou un menu : dix puces sur deux
/// lignes mangeraient une hauteur que l'écran n'a pas — barre haute et barre
/// d'onglets en prennent déjà cent vingt points — et un menu coûterait deux
/// gestes là où filtrer doit en coûter un.
///
/// Le vocabulaire est celui de `GameSwitch`, à dessein : fond cyan plein et
/// texte sombre pour la sélection, verre pour le reste. Deux contrôles qui font
/// le même travail sur trois écrans ne peuvent pas se présenter autrement.
///
/// Ce n'est PAS `GameSwitch` lui-même, et pas par oubli : celui-ci lie un `Game`
/// non optionnel, parce que la Carte et les Codes montrent toujours un jeu et un
/// seul. Le fil, lui, les mélange par défaut — « tous » n'a de sens qu'ici, et
/// l'ajouter là-bas compliquerait deux écrans pour le besoin d'un troisième.
struct FeedFilterBar: View {
    let games: [Game]
    let categories: [NewsCategory]
    let selectedGame: Game?
    let selectedCategory: NewsCategory?
    let onSelectGame: (Game?) -> Void
    let onSelectCategory: (NewsCategory?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if !games.isEmpty {
                        chip(
                            title: Text("feed.filter.game.all"),
                            isSelected: selectedGame == nil,
                            isRestriction: false,
                            accessibilityLabel: Text("feed.filter.game.all.a11y")
                        ) { onSelectGame(nil) }

                        ForEach(games) { game in
                            chip(
                                // Chiffres romains nus, jamais la marque, et
                                // `verbatim` parce qu'un chiffre romain s'écrit
                                // pareil dans les cinq langues.
                                title: Text(verbatim: game.shortLabel),
                                isSelected: selectedGame == game,
                                accessibilityLabel: Text(game == .leonida ? "map.game.upcoming" : "map.game.reference")
                            ) { onSelectGame(game) }
                        }

                        Rectangle()
                            .fill(.white.opacity(0.15))
                            .frame(width: 1, height: 20)
                            .padding(.horizontal, 2)
                            .accessibilityHidden(true)
                    }

                    chip(
                        title: Text("feed.filter.category.all"),
                        isSelected: selectedCategory == nil,
                        isRestriction: false,
                        accessibilityLabel: Text("feed.filter.category.all.a11y")
                    ) { onSelectCategory(nil) }

                    ForEach(categories, id: \.self) { category in
                        chip(
                            title: Text(category.titleKey),
                            symbol: category.symbolName,
                            isSelected: selectedCategory == category,
                            accessibilityLabel: Text(category.titleKey)
                        ) { onSelectCategory(category) }
                    }
                }
                // Les marges du fil sont posées par le `LazyVStack` ; la rangée
                // les reprend à l'intérieur du défilement pour que les puces
                // puissent glisser bord à bord au lieu de s'arrêter à 16 points.
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
        // Ciblée sur la rangée, et sur la sélection seule. C'est ce qui donne
        // au tap son retour immédiat — la capsule s'allume — sans embarquer le
        // remplacement du fil dans la même animation.
        .animation(.snappy, value: selectedGame)
        .animation(.snappy, value: selectedCategory)
    }

    /// - Parameter isRestriction: si cette puce POSE un filtre. Les deux puces
    ///   « tout » n'en posent pas : elles marquent l'absence de restriction, et
    ///   les allumer en cyan revenait à peindre en couleur d'accent l'état où il
    ///   ne se passe rien. Vu à l'écran, ça faisait deux capsules cyan
    ///   permanentes au-dessus d'un compte à rebours qui en porte déjà trois, et
    ///   surtout ça vidait le cyan de son sens — la couleur ne disait plus
    ///   « un filtre est posé », puisqu'elle était là par défaut.
    @ViewBuilder
    private func chip(
        title: Text,
        symbol: String? = nil,
        isSelected: Bool,
        isRestriction: Bool = true,
        accessibilityLabel: Text,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isSelected else { return }
            // SURTOUT PAS de `withAnimation` ici, et c'est mesuré.
            //
            // L'action remplace TOUT le contenu du fil. Enveloppée dans une
            // animation, SwiftUI animait l'apparition et la disparition de
            // dizaines de cartes portant chacune un `.glassEffect()` : douze
            // images perdues et jusqu'à 127 ms de blocage par tap, contre zéro
            // à une image sans elle (sonde `CADisplayLink`, iPhone 17). C'était
            // toute la latence ressentie.
            //
            // L'animation qu'on veut vraiment est celle de la PUCE, qui ne
            // concerne qu'une capsule : elle est posée en `.animation(_:value:)`
            // sur la rangée, où elle ne touche pas la liste.
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
            .foregroundStyle(textStyle(isSelected: isSelected, isRestriction: isRestriction))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Le verre TEINTÉ plutôt qu'une capsule pleine posée derrière lui :
            // `CompactTabBar` marque déjà sa sélection ainsi, et empiler un
            // fond opaque sous du verre revient à payer le verre sans le voir.
            .glassEffect(glass(isSelected: isSelected, isRestriction: isRestriction), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Trois états et non deux : cyan pour un filtre posé, verre blanchi pour la
    /// puce « tout » quand elle est active, verre nu pour le reste.
    private func glass(isSelected: Bool, isRestriction: Bool) -> Glass {
        guard isSelected else { return .regular.interactive() }
        return .regular
            .tint(isRestriction ? NCColor.neonCyan : .white.opacity(0.22))
            .interactive()
    }

    private func textStyle(isSelected: Bool, isRestriction: Bool) -> Color {
        guard isSelected else { return .white.opacity(0.8) }
        // Le cyan est assez clair pour exiger un texte sombre ; le verre
        // blanchi, lui, reste sombre et garde son texte en blanc.
        return isRestriction ? NCColor.nightSky : .white
    }
}
