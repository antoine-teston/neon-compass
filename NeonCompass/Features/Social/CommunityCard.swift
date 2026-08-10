import SwiftUI

struct CommunityCard: View {
    let community: PlayerCommunity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: community.name)
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(NCColor.neonCyan)
            }

            HStack(spacing: 6) {
                Text(LocalizedStringKey(community.platform.localizationKey))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.6))
                Text("·")
                    .foregroundStyle(.white.opacity(0.3))
                Text(verbatim: PlayerCommunity.memberBracket(for: community.memberCount))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(spacing: 4) {
                ForEach(community.playstyles.prefix(3)) { style in
                    Text(LocalizedStringKey(style.localizationKey))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.1), in: .capsule)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
