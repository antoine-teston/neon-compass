import SwiftUI
import SwiftData

struct ProfileScreen: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(\.modelContext) private var modelContext
    /// Fournis par `RootView`, qui les a repris à cet écran : la feuille de
    /// réglages s'ouvre désormais depuis la barre haute, donc depuis des onglets
    /// qui ne construisent jamais le Profil. C'est lui qui les charge aussi.
    @Environment(ProfileModel.self) private var profileModel
    @Environment(CommunityModel.self) private var communityModel: CommunityModel?
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    /// La jauge d'exploration est LOCALE : elle se lit ici, pas dans le
    /// profil serveur. `DiscoverySection` a déjà cette dépendance.
    @Environment(FoundStore.self) private var foundStore
    @Environment(AppModel.self) private var appModel
    @State private var showContributeHint = false

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    ProfileHeaderView(
                        state: ProfileHeaderState(
                            profile: profileModel.profile,
                            isLoadingProfile: profileModel.isLoadingProfile,
                            isProEntitled: proEntitlementModel.isProEntitled,
                            foundCount: foundStore.foundIDs.count,
                            pendingContributionCount: communityModel?.myContributions
                                .filter { $0.status == .pending }.count ?? 0
                        ),
                        onContribute: { showContributeHint = true }
                    )

                    DiscoverySection()

                    if authModel.userID != nil, serverFeatures.isEnabled, let communityModel {
                        myContributionsSection(communityModel)
                    }

                    if authModel.userID == nil {
                        signInInvitation
                    }
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showContributeHint) {
            ContributeHintSheet(onOpenMap: { appModel.openMapToContribute() })
        }
    }

    /// Invitation, pas obstacle : elle est en pied de page, sous toute la
    /// progression, et n'empêche rien.
    private var signInInvitation: some View {
        VStack(spacing: 8) {
            Text("profile.signIn.invitation")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("profile.signIn.open") { appModel.showsSignIn = true }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func myContributionsSection(_ communityModel: CommunityModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.myContributions.title")
                .font(NCTypography.body)
                .foregroundStyle(.white)
            if communityModel.myContributions.isEmpty {
                Text("profile.myContributions.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(communityModel.myContributions) { contribution in
                    HStack {
                        Text(contribution.title)
                        Spacer()
                        Text(statusKey(contribution.status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statusKey(_ status: Contribution.Status) -> LocalizedStringKey {
        switch status {
        case .pending: "profile.myContributions.status.pending"
        case .approved: "profile.myContributions.status.approved"
        case .rejected: "profile.myContributions.status.rejected"
        }
    }
}
