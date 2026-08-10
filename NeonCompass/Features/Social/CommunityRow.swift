import SwiftUI

struct CommunityRow: View {
    let community: PlayerCommunity

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: community.name)
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if community.isPromoted {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(NCColor.neonCyan)
                    }
                }
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(community.platform.localizationKey))
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                    ForEach(community.playstyles.prefix(2)) { style in
                        Text(LocalizedStringKey(style.localizationKey))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Spacer()
            if community.discordInvite != nil {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Text(verbatim: PlayerCommunity.memberBracket(for: community.memberCount))
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.4))
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}
