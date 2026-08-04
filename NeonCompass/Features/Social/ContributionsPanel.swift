import SwiftUI

/// Le volet Propositions de l'onglet Social.
///
/// C'est ICI qu'on vote, et plus dans le popover d'une épingle : voter c'est
/// parcourir ce qui vient d'être proposé, une épingle répond à « qu'est-ce qu'il
/// y a là ». Et avant la sortie du 19 novembre, la carte VI est vide — ce volet
/// est la seule surface où une contribution existe.
///
/// Pas de bascule V/VI : les contributions ne concernent que VI, et
/// `OnlineEventsModel.showsGamePicker` pose déjà la règle — pas de sélecteur
/// quand il n'y a rien à choisir. Le périmètre est dit en sous-titre.
struct ContributionsPanel: View {
    @Environment(AuthModel.self) private var authModel
    let communityModel: CommunityModel

    @State private var showSignInToContribute = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("social.proposals.subtitle")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)

            if communityModel.visibleSpots.isEmpty {
                emptyState
            } else {
                let sections = ContributionSections(
                    spots: communityModel.visibleSpots,
                    myVotes: communityModel.myVotes
                )
                if !sections.discover.isEmpty {
                    section("social.proposals.section.discover", spots: sections.discover)
                }
                if !sections.top.isEmpty {
                    section("social.proposals.section.top", spots: sections.top)
                }
            }
        }
        .signInToContributeAlert(isPresented: $showSignInToContribute)
    }

    private func section(_ titleKey: LocalizedStringKey, spots: [Contribution]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(NCTypography.cardMeta)
                .foregroundStyle(NCColor.neonCyan)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(spots) { spot in
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
        }
    }

    /// Pas de bannière publicitaire ici : la spec §5 la réserve aux écrans de
    /// LISTE, et un état vide n'en est pas un — même correctif que celui déjà
    /// appliqué à l'état vide des événements, où « on n'a rien pour toi, voilà
    /// une pub » avait été vu au simulateur.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("social.proposals.empty.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
            Text("social.proposals.empty.message")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
