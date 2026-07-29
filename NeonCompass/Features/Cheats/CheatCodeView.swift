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
/// Un `HStack` ne le fait pas — il compresse ou déborde — et le `Grid` de
/// SwiftUI demande un nombre de colonnes fixe, là où une séquence fait de quatre
/// à seize boutons. Une séquence tronquée est un code inutilisable, ce qui
/// justifie les trente lignes que ce `Layout` coûte.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total = CGSize.zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                total.width = max(total.width, rowWidth)
                total.height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        total.width = max(total.width, rowWidth)
        total.height += rowHeight
        return total
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
