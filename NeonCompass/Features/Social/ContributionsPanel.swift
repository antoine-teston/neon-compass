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
    @Environment(AppModel.self) private var appModel
    let communityModel: CommunityModel

    @State private var showSignInToContribute = false
    @State private var showContributeHint = false

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

            if communityModel.contributionsEnabled {
                contributeButton
            }
        }
        .signInToContributeAlert(isPresented: $showSignInToContribute)
        .sheet(isPresented: $showContributeHint) {
            ContributeHintSheet(onOpenMap: { appModel.openMapToContribute() })
        }
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

    /// La seule porte vers la soumission en dehors de la carte.
    ///
    /// `ContributionPlacement` n'est construit qu'à un endroit — le menu d'appui
    /// long de `MapScreen` — et rien n'annonçait ce geste ici. Or c'est ici que
    /// l'envie naît : on lit les propositions des autres, on vote, et on se dit
    /// qu'on en a une. Le profil avait déjà sa ligne d'invitation ; ce volet,
    /// lui, laissait l'élan sans issue.
    ///
    /// **En bas, pas en haut.** Le volet sert d'abord à voter ; une action
    /// secondaire posée avant la liste lui volerait l'accent. En bas elle arrive
    /// au moment où l'envie s'est formée, et l'état vide la met de toute façon
    /// sous les yeux.
    ///
    /// Déconnecté, on ouvre l'alerte plutôt que la feuille : envoyer quelqu'un
    /// sur la carte pour l'y refuser ferait deux écrans au lieu d'un. C'est la
    /// même condition que le vote juste au-dessus, donc la même alerte.
    private var contributeButton: some View {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("social.proposals.contribute.title")
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Text("social.proposals.contribute.detail")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.leading)
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
