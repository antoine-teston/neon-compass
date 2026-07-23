import SwiftUI
import SwiftData
import AuthenticationServices
import CryptoKit

struct ProfileScreen: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.modelContext) private var modelContext
    @State private var profileModel = ProfileModel(
        repository: FirestoreProfileRepository(),
        functions: FirebaseAccountFunctions()
    )
    @State private var communityModel: CommunityModel?
    @State private var currentNonce: String?
    @State private var showDeleteConfirmation = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 24) {
                if proEntitlementModel.isProEntitled {
                    Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(NCColor.neonCyan)
                } else {
                    Button("profile.pro.upgradeButton") { showPaywall = true }
                }
                if let userID = authModel.userID {
                    signedInContent(userID: userID)
                } else {
                    signedOutContent
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task(id: authModel.userID) {
            if let userID = authModel.userID {
                await profileModel.loadProfile(uid: userID)
                if communityModel == nil {
                    communityModel = CommunityModel(
                        repository: FirestoreContributionRepository(),
                        functions: FirebaseContributionFunctions(),
                        gateProvider: RemoteConfigCommunityGateProvider(),
                        modelContext: modelContext
                    )
                }
                await communityModel?.loadMyContributions(uid: userID)
            }
        }
        .onAppear { communityModel?.refreshBlockedAuthors() }
        .alert(
            "profile.deleteAccount.confirmTitle",
            isPresented: $showDeleteConfirmation
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) {}
            Button("profile.deleteAccount.confirmButton", role: .destructive) {
                Task {
                    try? await profileModel.deleteAccount()
                    try? authModel.signOut()
                }
            }
        } message: {
            Text("profile.deleteAccount.confirmMessage")
        }
    }

    private var signedOutContent: some View {
        VStack(spacing: 16) {
            Text("profile.signIn.prompt")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = []
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
        }
    }

    private func signedInContent(userID: String) -> some View {
        VStack(spacing: 16) {
            Text(profileModel.profile?.handle ?? "…")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)

            Button("profile.handle.regenerate") {
                Task { try? await profileModel.regenerateHandle() }
            }

            if let communityModel {
                myContributionsSection(communityModel)
                blockedContributorsSection(communityModel)
            }

            Button("profile.signOut") {
                try? authModel.signOut()
            }

            Button("profile.deleteAccount", role: .destructive) {
                showDeleteConfirmation = true
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

    private func blockedContributorsSection(_ communityModel: CommunityModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.blockedContributors.title")
                .font(NCTypography.body)
                .foregroundStyle(.white)
            if communityModel.blockedAuthorUIDs.isEmpty {
                Text("profile.blockedContributors.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(communityModel.blockedAuthorUIDs), id: \.self) { authorUid in
                    HStack {
                        Text(authorUid)
                        Spacer()
                        Button("profile.blockedContributors.unblock") {
                            communityModel.unblock(authorUid: authorUid)
                        }
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

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idTokenString = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            return
        }
        Task {
            try? await authModel.signIn(idTokenString: idTokenString, nonce: nonce)
        }
    }

    // Standard Firebase + Sign in with Apple boilerplate: a random nonce is
    // sent to Apple hashed (SHA256), and the raw nonce is sent to Firebase
    // alongside Apple's signed identity token — this round-trip is what lets
    // Firebase verify the token was issued for *this* sign-in attempt.
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
