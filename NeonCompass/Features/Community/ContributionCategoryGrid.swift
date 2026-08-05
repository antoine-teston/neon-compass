import SwiftUI

/// Les six catégories en pastilles, pour la soumission d'un lieu.
///
/// Elle remplace un `Picker` de menu qui obligeait à ouvrir une liste pour lire
/// six valeurs, alors que `POIPinPalette` donne à chacune un symbole et une
/// couleur — les mêmes que porteront l'épingle fantôme puis l'épingle publiée.
/// Choisir devient un tap, et le choix se relit d'un coup d'œil.
///
/// **Ce n'est pas `EditorCategoryGrid`, et c'est délibéré.** Celle-ci est
/// `#if DEBUG` avec des libellés en littéraux français : la fusionner traînerait
/// du code d'éditeur en Release, et ses libellés n'existent pas dans le
/// catalogue des cinq langues.
struct ContributionCategoryGrid: View {
    @Binding var selection: POICategory
    /// L'habillage courant de la carte : la pastille doit porter la couleur que
    /// l'épingle prendra réellement, et les deux habillages n'ont pas la même.
    let style: MapStyle

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(POICategory.allCases, id: \.self) { category in
                Button {
                    selection = category
                } label: {
                    tile(category)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func tile(_ category: POICategory) -> some View {
        let tint = POIPinPalette.color(for: category, style: style)
        let isSelected = category == selection
        return VStack(spacing: 5) {
            Image(systemName: POIPinPalette.symbol(for: category))
                .font(.system(size: 17, weight: .bold))
            Text(category.localizedNameKey)
                .font(NCTypography.cardMeta)
                // Six libellés traduits en cinq langues : « Collectible » et
                // « Sammelobjekt » n'ont pas la même longueur, et une grille
                // adaptative ne tolère pas qu'une case pousse les autres.
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(isSelected ? tint : .white.opacity(0.75))
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(isSelected ? 0.22 : 0.08))
                .overlay(
                    // Le halo est réservé à la sélection — jamais six accents
                    // lumineux à la fois, ce que le CLAUDE.md interdit
                    // explicitement (« glow on at most three accents »).
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(tint.opacity(isSelected ? 1 : 0.25), lineWidth: isSelected ? 1.5 : 1)
                )
        )
        .contentShape(.rect)
    }
}
