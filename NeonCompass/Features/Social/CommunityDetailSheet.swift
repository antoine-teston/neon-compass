import SwiftUI

struct CommunityDetailSheet: View {
    let community: PlayerCommunity
    let events: [CommunityEvent]
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !events.isEmpty { eventsSection }
                    discordButton
                }
                .padding(20)
            }
            .background(NCColor.nightSky.ignoresSafeArea())
            .navigationTitle(community.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("social.communities.detail.close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(community.platform.localizationKey))
                    .font(NCTypography.cardMeta)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.1), in: .capsule)
                Text(verbatim: PlayerCommunity.memberBracket(for: community.memberCount))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.6))
                if community.isPromoted {
                    Label("Spotlight", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(NCColor.neonCyan)
                }
            }
            .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 4) {
                ForEach(community.playstyles) { style in
                    Text(LocalizedStringKey(style.localizationKey))
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: .capsule)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("social.communities.detail.events")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            ForEach(events) { event in
                CommunityEventRow(event: event, communityName: community.name)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var discordButton: some View {
        if let invite = community.discordInvite, let url = URL(string: invite) {
            Button {
                openURL(url)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .foregroundStyle(NCColor.neonCyan)
                    Text("social.communities.detail.joinDiscord")
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }
}
