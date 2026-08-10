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
    let selectedCategory: CheatCategory?
    let onSelect: (CheatCategory?) -> Void

    var body: some View {
        FilterChipColumn {
            FilterChip(
                title: Text("cheats.filter.category.all"),
                isSelected: selectedCategory == nil,
                isRestriction: false,
                accessibilityLabel: Text("cheats.filter.category.all.a11y")
            ) { onSelect(nil) }

            ForEach(categories, id: \.self) { category in
                FilterChip(
                    title: Text(category.label),
                    symbol: category.symbolName,
                    isSelected: selectedCategory == category,
                    accessibilityLabel: Text(category.label)
                ) { onSelect(category) }
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
