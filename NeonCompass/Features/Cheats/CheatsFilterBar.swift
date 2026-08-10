import SwiftUI

/// Les puces de rubrique de l'écran Codes.
///
/// Mêmes puces que le fil d'actu, au composant près : un lecteur qui a appris à
/// filtrer sur un écran n'a pas à réapprendre sur l'autre. En COLONNE et non en
/// rangée, parce qu'ici elles ne sont pas là en permanence — elles se déplient
/// derrière un bouton, dans la géométrie du panneau de la carte.
///
/// Une seule rubrique à la fois, contrairement au `Set` que le modèle portait
/// depuis toujours sans que rien ne l'expose. La multi-sélection demanderait de
/// lire l'état de cinq puces pour savoir ce qu'on regarde ; une seule se lit
/// d'un coup d'œil, et c'est ce que fait déjà le fil.
struct CheatsFilterBar: View {
    let categories: [CheatCategory]
    let filter: CheatFilter
    /// Y a-t-il au moins un favori ? La puce ne s'affiche pas sinon : elle ne
    /// rendrait qu'une liste vide, et une commande qui ne peut rien faire est
    /// pire qu'absente.
    let hasFavorites: Bool
    let onSelect: (CheatFilter) -> Void

    var body: some View {
        FilterChipColumn {
            FilterChip(
                title: Text("cheats.filter.category.all"),
                isSelected: filter == .none,
                isRestriction: false,
                accessibilityLabel: Text("cheats.filter.category.all.a11y")
            ) { onSelect(.none) }

            ForEach(categories, id: \.self) { category in
                FilterChip(
                    title: Text(category.label),
                    symbol: category.symbolName,
                    isSelected: filter == .category(category),
                    accessibilityLabel: Text(category.label)
                ) { onSelect(.category(category)) }
            }

            // En BAS de la colonne et non en tête, séparée : la colonne descend
            // du bouton, donc son dernier élément est le plus loin de lui — et
            // « Favoris » n'est pas une rubrique de plus, c'est une restriction
            // d'un autre ordre. Le séparateur le dit avant qu'on ait lu.
            if hasFavorites {
                FilterChipDivider(axis: .vertical)
                FilterChip(
                    title: Text("cheats.favorites.title"),
                    symbol: "star.fill",
                    isSelected: filter == .favorites,
                    accessibilityLabel: Text("cheats.favorites.title")
                ) { onSelect(.favorites) }
            }
        }
    }
}

extension CheatCategory {
    /// Le symbole qui accompagne la rubrique sur sa puce.
    ///
    /// Les puces de l'actu en portent un : sans lui, cinq capsules de texte se
    /// ressemblent trop pour être visées vite. Choisis pour se distinguer entre
    /// eux plutôt que pour illustrer — c'est un repère, pas une illustration.
    var symbolName: String {
        switch self {
        case .player: "figure.stand"
        case .weapons: "scope"
        case .vehicles: "car.fill"
        case .world: "globe.europe.africa"
        case .misc: "sparkles"
        }
    }
}
