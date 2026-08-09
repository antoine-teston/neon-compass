import SwiftUI

/// Les puces de filtre du fil : le jeu, puis la rubrique.
///
/// La puce et la rangée vivent dans `Core/DesignSystem/FilterChip.swift` :
/// l'écran Codes emploie la même rangée, et un second exemplaire aurait divergé.
///
/// Ce n'est PAS `GameSwitch`, et pas par oubli : celui-ci lie un `Game` non
/// optionnel, parce que la Carte et les Codes montrent toujours un jeu et un
/// seul. Le fil, lui, les mélange par défaut — « les deux » n'a de sens qu'ici,
/// et l'ajouter là-bas compliquerait deux écrans pour le besoin d'un troisième.
struct FeedFilterBar: View {
    let games: [Game]
    let categories: [NewsCategory]
    let selectedGame: Game?
    let selectedCategory: NewsCategory?
    let onSelectGame: (Game?) -> Void
    let onSelectCategory: (NewsCategory?) -> Void

    var body: some View {
        FilterChipRow(animationTrigger: AnyHashable([selectedGame?.rawValue, selectedCategory?.rawValue])) {
            if !games.isEmpty {
                FilterChip(
                    title: Text("feed.filter.game.all"),
                    isSelected: selectedGame == nil,
                    isRestriction: false,
                    accessibilityLabel: Text("feed.filter.game.all.a11y")
                ) { onSelectGame(nil) }

                ForEach(games) { game in
                    FilterChip(
                        // Chiffres romains nus, jamais la marque, et `verbatim`
                        // parce qu'un chiffre romain s'écrit pareil dans les
                        // cinq langues.
                        title: Text(verbatim: game.shortLabel),
                        isSelected: selectedGame == game,
                        breathes: game == .leonida,
                        accessibilityLabel: Text(game == .leonida ? "map.game.upcoming" : "map.game.reference")
                    ) { onSelectGame(game) }
                }

                FilterChipDivider()
            }

            FilterChip(
                title: Text("feed.filter.category.all"),
                isSelected: selectedCategory == nil,
                isRestriction: false,
                accessibilityLabel: Text("feed.filter.category.all.a11y")
            ) { onSelectCategory(nil) }

            ForEach(categories, id: \.self) { category in
                FilterChip(
                    title: Text(category.titleKey),
                    symbol: category.symbolName,
                    isSelected: selectedCategory == category,
                    accessibilityLabel: Text(category.titleKey)
                ) { onSelectCategory(category) }
            }
        }
    }
}
