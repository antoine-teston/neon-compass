import SwiftUI

/// L'ordre du hub, réduit à une fonction pure pour être testé sans fixture.
enum VotePreview {
    static func spots<T>(discover: [T], top: [T], limit: Int = 3) -> [T] {
        Array((discover + top).prefix(limit))
    }
}

/// Le module primordial du hub : c'est lui qui alimente la carte VI en POI.
/// Trois propositions, vote inline sans naviguer, pastille locale, et la porte
/// « proposer » remontée — l'élan naît en votant.
struct VoteModule: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(AppModel.self) private var appModel

    let communityModel: CommunityModel
    /// Posé par l'écran en largeur régulière (panneau latéral) ; nil en
    /// compact, où le module présente sa propre feuille.
    var onSeeAll: (() -> Void)? = nil

    @State private var showsAll = false
    @State private var showSignInToContribute = false
    @State private var showContributeHint = false

    var body: some View {
        let sections = ContributionSections(spots: communityModel.visibleSpots, myVotes: communityModel.myVotes)
        let preview = VotePreview.spots(discover: sections.discover, top: sections.top)
        let unvoted = SocialHubVisibility.unvotedCount(
            spotIDs: communityModel.visibleSpots.map(\.id),
            votedIDs: Set(communityModel.myVotes.keys)
        )

        VStack(alignment: .leading, spacing: 12) {
            header(unvoted: unvoted)
            ForEach(preview) { spot in
                ContributionRow(
                    spot: spot,
                    myVote: communityModel.myVotes[spot.id],
                    onVote: { direction in
                        guard authModel.userID != nil else {
                            showSignInToContribute = true
                            return
                        }
                        Task { await communityModel.vote(on: spot, direction: direction) }
                    },
                    onReport: { Task { await communityModel.report(spot, reason: nil) } },
                    onBlockAuthor: {
                        if let authorUid = spot.authorUid {
                            communityModel.block(authorUid: authorUid, handle: spot.authorHandle)
                        }
                    }
                )
            }
            if communityModel.contributionsEnabled {
                proposeRow
            }
        }
        .sheet(isPresented: $showsAll) { ProposalsSheet(communityModel: communityModel) }
        .signInToContributeAlert(isPresented: $showSignInToContribute)
        .sheet(isPresented: $showContributeHint) {
            ContributeHintSheet(onOpenMap: { appModel.openMapToContribute() })
        }
    }

    private func header(unvoted: Int) -> some View {
        HStack(spacing: 8) {
            Text("social.hub.vote.title")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            if unvoted > 0 {
                // Le second accent cyan de l'écran, avec le rebours — et le
                // dernier : tout le reste du hub reste sobre.
                Text(unvoted, format: .number)
                    .font(.caption2.bold())
                    .foregroundStyle(NCColor.nightSky)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(NCColor.neonCyan, in: .capsule)
            }
            Spacer()
            Button {
                if let onSeeAll { onSeeAll() } else { showsAll = true }
            } label: {
                HStack(spacing: 3) {
                    Text("social.hub.seeAll")
                    Image(systemName: "chevron.right").font(.caption2.bold())
                }
                .font(NCTypography.cardMeta)
                .foregroundStyle(NCColor.neonCyan)
            }
            .buttonStyle(.plain)
        }
    }

    /// La même porte que le volet d'avant, en une ligne : mêmes gardes
    /// (alerte si déconnecté, feuille d'explication sinon), même destination.
    private var proposeRow: some View {
        Button {
            guard authModel.userID != nil else {
                showSignInToContribute = true
                return
            }
            showContributeHint = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(NCColor.neonCyan)
                Text("social.proposals.contribute.title")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
