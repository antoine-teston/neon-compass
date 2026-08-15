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
                // Les deux cartes existent en deux habillages : plus de garde à
                // poser ici, le bouton n'est jamais mort.
                styleButton
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

    /// Le contrôle lui-même vit dans `Core/DesignSystem/GameSwitch.swift` :
    /// l'écran Codes en a besoin aussi, et un second exemplaire aurait divergé.
    private var gameSwitch: some View {
        GameSwitch(game: $game)
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
