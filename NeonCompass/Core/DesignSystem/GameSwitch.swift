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
                    // SURTOUT PAS de `withAnimation` ici, et c'est mesuré.
                    //
                    // Ce contrôle change le jeu affiché, ce qui remplace tout le
                    // contenu de l'écran qui l'héberge. Enveloppée dans une
                    // animation, la bascule faisait animer par SwiftUI
                    // l'apparition et la disparition de toute une colonne de
                    // cartes en verre : sur l'écran Codes, quarante images
                    // perdues sur six bascules contre huit sans, et des pics de
                    // 238 ms au lieu de 72 (sonde `CADisplayLink`, iPhone 17).
                    //
                    // L'animation qu'on veut est celle des deux pastilles, et
                    // elle est posée en `.animation(_:value:)` sur la capsule.
                    // Le même remède qu'a reçu `FeedFilterBar`.
                    game = candidate
                } label: {
                    Text(candidate.shortLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(candidate == game ? NCColor.nightSky : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(candidate == game ? NCColor.neonCyan : .clear)
                        )
                        .breathingHighlight(candidate == .leonida)
                }
                .accessibilityLabel(
                    Text(candidate == .leonida ? "map.game.upcoming" : "map.game.reference")
                )
                .accessibilityAddTraits(candidate == game ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        // Ciblée sur la capsule : le tap garde son retour immédiat, sans
        // embarquer dans la même animation le contenu que la bascule remplace.
        .animation(.snappy, value: game)
    }
}
