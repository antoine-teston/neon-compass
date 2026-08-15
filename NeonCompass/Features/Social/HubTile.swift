import SwiftUI

/// Le gabarit « tuile » du hub : demi-largeur, un titre en petites capitales,
/// une ligne vivante, une sous-ligne, un chevron. Toute la tuile est le bouton.
struct HubTile<Main: View, Sub: View>: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let main: Main
    @ViewBuilder let sub: Sub

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(titleKey)
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.35))
                }
                main
                Spacer(minLength: 0)
                sub
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
