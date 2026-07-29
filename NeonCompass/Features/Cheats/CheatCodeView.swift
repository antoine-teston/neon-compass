import SwiftUI

/// Rend un code dans la forme qu'impose son mode de saisie.
///
/// Un seul endroit sait qu'une séquence se lit en glyphes, qu'un mot-clé se
/// tape et qu'un numéro se compose : la carte et le lecteur plein écran
/// partagent cette vue et ne diffèrent que par `glyphSize`.
struct CheatCodeView: View {
    let code: CheatCode
    let glyphSize: CGFloat
    var showsCopyButton: Bool = true

    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .center, spacing: glyphSize * 0.4) {
            switch code {
            case .buttons(let buttons):
                buttonRow(buttons)
            case .keyword(let keyword):
                textCode(keyword, hint: "cheats.code.pc.hint")
            case .phone(let number, let mnemonic):
                phoneCode(number, mnemonic: mnemonic)
            }
            if showsCopyButton, let text = code.copyableText {
                Spacer(minLength: 8)
                copyButton(text)
            }
        }
    }

    /// Enveloppée : une séquence de douze boutons dépasse la largeur d'un iPhone
    /// en compact, et une rangée qui déborde coupe la fin du code — c'est-à-dire
    /// la seule information que l'écran existe pour transmettre.
    private func buttonRow(_ buttons: [GamepadButton]) -> some View {
        FlowLayout(spacing: glyphSize * 0.35) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                Image(systemName: GamepadGlyph.systemImage(for: button))
                    .font(.system(size: glyphSize))
                    .foregroundStyle(NCColor.neonCyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textCode(_ text: String, hint: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(size: glyphSize * 0.8, weight: .heavy, design: .monospaced))
                .foregroundStyle(NCColor.neonCyan)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phoneCode(_ number: String, mnemonic: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(number)
                .font(.system(size: glyphSize * 0.8, weight: .heavy, design: .monospaced))
                .foregroundStyle(NCColor.neonCyan)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            // Le mnémonique est ce qui rend un numéro mémorisable ; il est
            // secondaire à l'écran, mais c'est lui qu'on retient.
            if let mnemonic {
                Text(mnemonic)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("cheats.code.phone.hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            Clipboard.copy(text)
            didCopy = true
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(didCopy ? NCColor.neonCyan : .secondary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(didCopy ? Text("cheats.code.copied") : Text("cheats.code.copy"))
        .sensoryFeedback(.success, trigger: didCopy)
    }
}

/// Disposition en flux : les enfants s'alignent en rangée et passent à la ligne
/// quand la largeur manque.
///
/// Un `HStack` ne le fait pas — il compresse ou déborde — et un `LazyVGrid` à
/// colonnes adaptatives répartit l'espace restant entre ses colonnes, ce qui
/// étale une séquence de quatre boutons sur toute la largeur au lieu de la
/// donner à lire comme une suite. Une séquence fait de quatre à seize boutons :
/// il faut un vrai passage à la ligne.
///
/// Une première version mesurait et plaçait selon deux règles écrites
/// séparément, et mesurait avec `proposal.width ?? .infinity`. Interrogée sans
/// largeur — ce que fait un `HStack` pour jauger la souplesse de ses enfants —
/// elle annonçait donc UNE rangée, puis en plaçait deux : la seconde sortait de
/// la carte par le bas. D'où le calcul unique ci-dessous, partagé par les deux
/// passes, et la largeur de secours finie.
struct FlowLayout: Layout {
    var spacing: CGFloat

    /// Largeur retenue quand aucune n'est proposée. Finie, délibérément : une
    /// largeur infinie mesure une rangée unique, et c'est cette réponse-là qui
    /// faisait déborder les glyphes.
    private static let fallbackWidth: CGFloat = 320

    private struct Row {
        var positions: [CGPoint] = []
        var height: CGFloat = 0
        var width: CGFloat = 0
    }

    /// Seul endroit qui décide où va quoi. Mesure et placement en dérivent tous
    /// les deux, donc ils ne peuvent pas se contredire.
    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, rows: [Row]) {
        var rows: [Row] = []
        var current = Row()
        var y: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.positions.isEmpty ? size.width : current.width + spacing + size.width
            if !current.positions.isEmpty, needed > maxWidth {
                rows.append(current)
                y += current.height + spacing
                current = Row()
            }
            let x = current.positions.isEmpty ? 0 : current.width + spacing
            current.positions.append(CGPoint(x: x, y: y))
            current.width = x + size.width
            current.height = max(current.height, size.height)
        }
        if !current.positions.isEmpty { rows.append(current) }

        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + spacing * CGFloat(max(0, rows.count - 1))
        return (CGSize(width: width, height: height), rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        rows(subviews, maxWidth: proposal.width ?? Self.fallbackWidth).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        let laid = rows(subviews, maxWidth: bounds.width).rows
        var index = 0
        for row in laid {
            for point in row.positions {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                index += 1
            }
        }
    }
}
