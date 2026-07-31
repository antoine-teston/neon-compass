import SwiftUI
import SwiftData

struct ProfileScreen: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(\.modelContext) private var modelContext
    @State private var profileModel = ProfileModel(
        repository: FirestoreProfileRepository(),
        functions: FirebaseAccountFunctions(),
        localDeletion: FirebaseClientAccountDeletion()
    )
    @State private var communityModel: CommunityModel?
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @State private var showSettings = false

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(Text("settings.title"))
                }
                if let userID = authModel.userID {
                    signedInContent(userID: userID)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen(profileModel: profileModel, communityModel: communityModel)
        }
        .task(id: authModel.userID) {
            if let userID = authModel.userID {
                await profileModel.loadProfile(uid: userID)
                if communityModel == nil {
                    communityModel = CommunityModel.live(modelContext: modelContext)
                }
                await communityModel?.loadMyContributions(uid: userID)
            }
        }
    }

    private func signedInContent(userID: String) -> some View {
        VStack(spacing: 16) {
            // Pseudo, XP, régénération et contributions viennent tous de Cloud
            // Functions (createUserProfile, regenerateHandle, submitContribution).
            // Sans elles, le pseudo resterait un « … » perpétuel et les boutons
            // échoueraient en silence.
            if serverFeatures.isEnabled {
                Text(profileModel.profile?.handle ?? "…")
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(NCColor.neonCyan)

                if let profile = profileModel.profile {
                    levelBadge(profile)
                }

                if let communityModel {
                    myContributionsSection(communityModel)
                }
            }
        }
    }

    private func levelBadge(_ profile: Profile) -> some View {
        HStack {
            Text(String(format: String(localized: "profile.level.format"), profile.level))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)
            Spacer()
            Text(String(format: String(localized: "profile.xp.format"), profile.xp))
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
