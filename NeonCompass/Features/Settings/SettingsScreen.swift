import SwiftUI
import SwiftData
import AuthenticationServices
import UIKit

/// Feuille de réglages, ouverte depuis l'entête du Profil.
///
/// En feuille et pas en `toolbar` : aucun écran d'onglet n'a de
/// `NavigationStack` — `RootView` les empile dans un `ZStack` sous une barre
/// maison — donc un `ToolbarItem` ne s'afficherait nulle part, sans erreur ni
/// avertissement. Même motif que `PaywallView`.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(ThemeStore.self) private var themeStore
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @Environment(\.modelContext) private var modelContext

    let profileModel: ProfileModel
    let communityModel: CommunityModel?

    @State private var settingsModel: SettingsModel
    @State private var followedCategoriesStore = FollowedCategoriesStore(
        notifier: FirebaseFollowedCategoryNotifier()
    )
    @State private var showDeleteConfirmation = false
    @State private var showPaywall = false
    @State private var currentNonce: String?
    @State private var signInError: String?

    init(profileModel: ProfileModel, communityModel: CommunityModel?) {
        self.profileModel = profileModel
        self.communityModel = communityModel
        _settingsModel = State(initialValue: SettingsModel(profileModel: profileModel))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if proEntitlementModel.isProEntitled {
                        Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(NCColor.neonCyan)
                        // Les notifications suivies sont envoyées par une Cloud
                        // Function : sans elle, l'écran promettrait un service
                        // qui n'arrive jamais.
                        if serverFeatures.isEnabled {
                            followedCategoriesSection
                        }
                        themeSection
                        iconSection
                    } else {
                        Button("profile.pro.upgradeButton") { showPaywall = true }
                    }

                    if let communityModel {
                        blockedContributorsSection(communityModel)
                    }

                    accountSection
                }
                .padding(24)
            }
            .background(NCColor.nightSky.ignoresSafeArea())
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("settings.done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear { communityModel?.refreshBlockedAuthors() }
        .alert(
            "profile.deleteAccount.confirmTitle",
            isPresented: $showDeleteConfirmation
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) {}
            Button("profile.deleteAccount.confirmButton", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("profile.deleteAccount.confirmMessage")
        }
        .alert(
            "profile.deleteAccount.failed",
            isPresented: Binding(
                get: { settingsModel.deletionFailed },
                set: { if !$0 { settingsModel.dismissDeletionFailure() } }
            )
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) {
                settingsModel.dismissDeletionFailure()
            }
        }
        .alert(
            "profile.signIn.failed",
            isPresented: Binding(get: { signInError != nil }, set: { if !$0 { signInError = nil } })
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) { signInError = nil }
        } message: {
            // Le détail technique n'est pas traduit : il vient du système ou de
            // Firebase, et c'est lui qui permet de comprendre le blocage.
            Text(signInError ?? "")
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if authModel.userID == nil {
                Text(serverFeatures.isEnabled ? "profile.signIn.prompt" : "profile.signIn.syncOnlyPrompt")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.85))

                SignInWithAppleButton(.signIn) { request in
                    let nonce = AppleSignInCoordinator.makeRawNonce()
                    currentNonce = nonce
                    request.requestedScopes = []
                    request.nonce = AppleSignInCoordinator.sha256(nonce)
                } onCompletion: { result in
                    handleSignInResult(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 44)
            } else {
                if serverFeatures.isEnabled {
                    Button("profile.handle.regenerate") {
                        Task { try? await profileModel.regenerateHandle() }
                    }
                }
                Button("profile.signOut") { try? authModel.signOut() }
                Button("profile.deleteAccount", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
    }

    private func deleteAccount() async {
        guard let userID = authModel.userID else { return }
        if await settingsModel.deleteAccount(uid: userID, serverEnabled: serverFeatures.isEnabled) {
            try? authModel.signOut()
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.theme.title")
                .font(NCTypography.body)
                .foregroundStyle(.white)
            Picker(
                selection: Binding(
                    get: { themeStore.selectedTheme },
                    set: { themeStore.selectTheme($0) }
                )
            ) {
                ForEach(NCTheme.allCases) { theme in
                    Text(theme.nameKey)
                        .tag(theme)
                        .foregroundStyle(theme.accent)
                }
            } label: {
                Text("profile.theme.title")
            }
            .pickerStyle(.segmented)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "profile.icon.title",
                isOn: Binding(
                    get: { UIApplication.shared.alternateIconName != nil },
                    set: { themeStore.setAlternateIcon(named: $0 ? Self.neonIconName : nil) }
                )
            )
            .foregroundStyle(.white)
        }
    }

    // Assumes the "AppIcon-Neon" asset-catalog icon set will exist once a
    // designer creates it (see docs/ops/2026-07-23-alternate-app-icons.md);
    // this string is not yet declared anywhere in project.yml/Info.plist, so
    // toggling this on a current build silently no-ops via UIKit's
    // completion handler until that follow-up ships.
    private static let neonIconName = "AppIcon-Neon"

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

    private var followedCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.followedCategories.title")
                .font(NCTypography.body)
                .foregroundStyle(.white)
            ForEach(POICategory.allCases, id: \.self) { category in
                Toggle(
                    isOn: Binding(
                        get: { followedCategoriesStore.followedCategories.contains(category) },
                        set: { _ in
                            Task { await followedCategoriesStore.toggle(category) }
                        }
                    )
                ) {
                    Text(category.localizedNameKey)
                }
            }
        }
    }

    /// Chaque échec est désormais dit. La version précédente les avalait tous —
    /// `guard … else { return }` puis `try?` — donc un utilisateur bloqué n'avait
    /// aucun moyen de savoir pourquoi, et nous non plus. C'est la seule
    /// connexion de l'app : elle ne peut pas échouer en silence.
    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            report(AppleSignInCoordinator.classify(error: error))
        case .success(let authorization):
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential
            switch AppleSignInCoordinator.resolve(credential: credential, rawNonce: currentNonce) {
            case .failure(let failure):
                report(failure)
            case .success(let value):
                Task {
                    do {
                        try await authModel.signIn(idTokenString: value.idToken, nonce: value.nonce)
                    } catch {
                        report(.underlying(error.localizedDescription))
                    }
                }
            }
        }
    }

    private func report(_ failure: AppleSignInFailure) {
        let message: String
        switch failure {
        case .canceled: return
        case .unexpectedCredentialType: message = String(localized: "profile.signIn.unexpectedCredential")
        case .missingIdentityToken: message = String(localized: "profile.signIn.missingToken")
        case .missingNonce: message = String(localized: "profile.signIn.missingNonce")
        case .underlying(let detail): message = detail
        }
        // Imprimé en plus de l'alerte : c'est ce qui rend le diagnostic
        // possible depuis les journaux du simulateur.
        print("ProfileScreen: connexion refusée — \(message)")
        signInError = message
    }
}
