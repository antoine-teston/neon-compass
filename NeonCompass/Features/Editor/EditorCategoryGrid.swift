#if DEBUG
import SwiftUI

/// Grille des six catégories, présentée juste après un appui long.
///
/// Un tap suffit : ni champ texte, ni confirmation. C'est le geste des trois
/// secondes, pensé pour qu'on ne quitte pas le jeu des yeux plus d'un instant —
/// la rédaction se fera au Mac.
///
/// Libellés en littéraux français, contrairement au reste de l'app : l'éditeur
/// n'est jamais livré, lui écrire cinq traductions serait du travail pur perte
/// (écart à CLAUDE.md assumé, cf. spec).
struct EditorCategoryGrid: View {
    let onPick: (POICategory) -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        VStack(spacing: 16) {
            Text("Catégorie")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(POICategory.allCases, id: \.self) { category in
                    Button {
                        onPick(category)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: POIPinPalette.symbol(for: category))
                                .font(.system(size: 22, weight: .bold))
                            Text(Self.label(for: category))
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(POIPinPalette.color(for: category, style: .neon).opacity(0.35))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Annuler", action: onCancel)
                .foregroundStyle(NCColor.neonCyan)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NCColor.nightSky)
    }

    static func label(for category: POICategory) -> String {
        switch category {
        case .landmark: "Lieu"
        case .collectible: "Collectible"
        case .activity: "Activité"
        case .safehouse: "Planque"
        case .vehicle: "Véhicule"
        case .event: "Événement"
        }
    }
}
#endif
