import SwiftUI

/// Bascule entre les deux jeux.
///
/// Extraite de `MapDisplayControls`, où elle vivait en privé, quand l'écran
/// Codes en a eu besoin à son tour. Un second exemplaire aurait divergé — c'est
/// exactement ce qui était arrivé à `MapGame` et `NewsGame`, deux énumérations
/// jumelles dont l'une prétendait réutiliser le vocabulaire de l'autre.
///
/// Chiffres romains nus, jamais la marque : CLAUDE.md interdit les marques
/// déposées dans l'app.
///
/// L'ordre est celui de l'énumération — le jeu à venir d'abord, la référence
/// ensuite — parce que l'app est la compagne du premier. Il est le même sur les
/// deux écrans : deux contrôles d'apparence identique dont l'ordre diffèrerait
/// seraient pires que n'importe lequel des deux ordres.
struct GameSwitch: View {
    @Binding var game: Game

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Game.allCases) { candidate in
                Button {
                    guard candidate != game else { return }
                    withAnimation(.snappy) { game = candidate }
                } label: {
                    Text(candidate.shortLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(candidate == game ? NCColor.nightSky : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(candidate == game ? NCColor.neonCyan : .clear)
                        )
                }
                .accessibilityLabel(
                    Text(candidate == .leonida ? "map.game.upcoming" : "map.game.reference")
                )
                .accessibilityAddTraits(candidate == game ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
