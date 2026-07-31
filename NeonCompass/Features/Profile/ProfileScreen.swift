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
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @State private var showSettings = false

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 24) {
                ProfileHeaderView(
                    profile: profileModel.profile,
                    // La garde que portait l'ancien `if serverFeatures.isEnabled` :
                    // sans Cloud Functions, `loadProfile` ne trouve aucun document
                    // et le pseudo resterait un « … » perpétuel.
                    isSignedIn: authModel.userID != nil && serverFeatures.isEnabled,
                    isProEntitled: proEntitlementModel.isProEntitled,
                    pendingContributionCount: communityModel?.myContributions
                        .filter { $0.status == .pending }.count ?? 0,
                    onOpenSettings: { showSettings = true }
                )
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
            // La liste des contributions vient de submitContribution (Cloud
            // Function) : sans elle, ce bloc n'aurait rien à afficher. Le
            // pseudo et l'XP sont désormais portés par ProfileHeaderView.
            if serverFeatures.isEnabled {
                if let communityModel {
                    myContributionsSection(communityModel)
                }
            }
        }
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
