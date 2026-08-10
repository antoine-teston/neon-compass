import SwiftUI

struct CommunitiesPanel: View {
    let model: CommunitiesModel

    @Environment(AuthModel.self) private var authModel
    @State private var selectedCommunity: PlayerCommunity?
    @State private var showCreateSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.promotedCommunities.isEmpty {
                spotlight
            }

            if !model.upcomingEvents.isEmpty {
                eventsPreview
            }

            filters
            communityList

            if authModel.userID != nil {
                createButton
            }
        }
        .sheet(item: $selectedCommunity) { community in
            CommunityDetailSheet(
                community: community,
                events: model.upcomingEvents.filter { $0.communityID == community.id }
            )
        }
    }

    private var spotlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("social.communities.spotlight")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.promotedCommunities.prefix(5)) { community in
                        Button { selectedCommunity = community } label: {
                            CommunityCard(community: community)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var eventsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("social.communities.upcomingEvents")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(model.upcomingEvents.prefix(5)) { event in
                    let name = model.communities.first { $0.id == event.communityID }?.name ?? ""
                    Button { selectCommunity(for: event) } label: {
                        CommunityEventRow(event: event, communityName: name)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    label: "social.communities.filter.platform",
                    value: model.platformFilter?.localizationKey,
                    onClear: { model.platformFilter = nil }
                )
                filterChip(
                    label: "social.communities.filter.playstyle",
                    value: model.playstyleFilter?.localizationKey,
                    onClear: { model.playstyleFilter = nil }
                )
            }
        }
    }

    private func filterChip(label: LocalizedStringKey, value: String?, onClear: @escaping () -> Void) -> some View {
        Menu {
            if label == "social.communities.filter.platform" {
                ForEach(CommunityPlatform.allCases) { p in
                    Button { model.platformFilter = p } label: {
                        Text(LocalizedStringKey(p.localizationKey))
                    }
                }
            } else {
                ForEach(CommunityPlaystyle.allCases) { s in
                    Button { model.playstyleFilter = s } label: {
                        Text(LocalizedStringKey(s.localizationKey))
                    }
                }
            }
            if value != nil {
                Divider()
                Button(role: .destructive, action: onClear) {
                    Text("social.communities.filter.clear")
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let value {
                    Text(LocalizedStringKey(value))
                } else {
                    Text(label)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(NCTypography.cardMeta)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(value != nil ? NCColor.neonCyan : .white.opacity(0.6))
            .background(.white.opacity(value != nil ? 0.12 : 0.06), in: .capsule)
        }
    }

    private var communityList: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.filteredCommunities) { community in
                Button { selectedCommunity = community } label: {
                    CommunityRow(community: community)
                }
                .buttonStyle(.plain)
            }

            if model.filteredCommunities.isEmpty {
                Text("social.communities.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }

    private var createButton: some View {
        Button { showCreateSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(NCColor.neonCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("social.communities.create.button")
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                    Text("social.communities.create.buttonDetail")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCreateSheet) {
            CreateCommunitySheet(model: model)
        }
    }

    private func selectCommunity(for event: CommunityEvent) {
        selectedCommunity = model.communities.first { $0.id == event.communityID }
    }
}
