import SwiftUI

struct CheatCard: View {
    let cheat: Cheat
    let platform: Platform
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(cheat.effect.en)
                        .font(NCTypography.body.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? NCColor.sunsetOrange : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    ForEach(Array((cheat.sequence[platform] ?? []).enumerated()), id: \.offset) { _, button in
                        Image(systemName: GamepadGlyph.systemImage(for: button, platform: platform))
                            .font(.system(size: 18))
                            .foregroundStyle(NCColor.neonCyan)
                    }
                    Spacer()
                    if cheat.blocksTrophies {
                        Text("cheats.blocksTrophies")
                            .font(.caption2)
                            .foregroundStyle(NCColor.sunsetMagenta)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
