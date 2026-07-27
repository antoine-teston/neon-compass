import SwiftUI

/// Contrôles d'affichage de la carte, ancrés en bas à droite — séparés de
/// `MapFilterControls` (barre haute) parce qu'ils ne filtrent rien : ils
/// changent QUELLE carte on regarde et sous quel habillage. Les garder à
/// portée du pouce compte, on y touche en cours d'exploration.
struct MapDisplayControls: View {
    @Binding var game: MapGame
    @Binding var style: MapStyle
#if DEBUG
    /// Nil quand l'éditeur n'est pas disponible sur la carte affichée — le
    /// bouton disparaît alors complètement plutôt que d'être grisé : sur la
    /// carte de référence il n'y a rien à éditer, ce n'est pas un manque.
    var editorArmed: Binding<Bool>?
#endif

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .trailing, spacing: 12) {
                gameSwitch
                // La carte du jeu à venir n'a qu'un habillage : proposer une
                // bascule sans effet serait un bouton mort.
                if game.supportsStyleToggle {
                    styleButton
                }
#if DEBUG
                if let editorArmed {
                    editorButton(armed: editorArmed)
                }
#endif
            }
        }
    }

#if DEBUG
    private func editorButton(armed: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { armed.wrappedValue.toggle() }
        } label: {
            Image(systemName: armed.wrappedValue ? "pencil.circle.fill" : "pencil.circle")
                .font(.system(size: 20))
                .foregroundStyle(armed.wrappedValue ? NCColor.sunsetOrange : .white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Mode éditeur"))
    }
#endif

    /// Chiffres romains nus, jamais la marque : CLAUDE.md interdit les marques
    /// déposées dans l'app.
    private var gameSwitch: some View {
        HStack(spacing: 4) {
            ForEach(MapGame.allCases) { candidate in
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
                .accessibilityLabel(Text(candidate == .leonida ? "map.game.upcoming" : "map.game.reference"))
                .accessibilityAddTraits(candidate == game ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var styleButton: some View {
        Button {
            withAnimation(.snappy) { style = style == .neon ? .classic : .neon }
        } label: {
            Image(systemName: style == .neon ? "paintpalette.fill" : "paintpalette")
                .font(.system(size: 20))
                .foregroundStyle(style == .neon ? NCColor.neonCyan : .white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("map.style.toggle"))
    }
}
