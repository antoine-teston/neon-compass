import SwiftUI
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

    let profileModel: ProfileModel
    let communityModel: CommunityModel?

    @State private var settingsModel: SettingsModel
    @State private var followedCategoriesStore = FollowedCategoriesStore(
        notifier: APNsFollowedCategoryNotifier.shared
    )
    @State private var showDeleteConfirmation = false
    @State private var showPaywall = false
    @State private var currentNonce: String?
    @State private var signInError: String?
    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""

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

                    if serverFeatures.isEnabled, let communityModel {
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

                // Apple en premier, et en tête : la règle App Store 4.8 l'exige
                // dès qu'un autre fournisseur tiers est proposé.
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

                Button {
                    Task {
                        do { try await authModel.signInWithGoogle() } catch { reportSignIn(error) }
                    }
                } label: {
                    Text("profile.signIn.google")
                        .font(NCTypography.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white.opacity(0.12), in: .rect(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                emailSection
            } else {
                if serverFeatures.isEnabled {
                    Button("profile.handle.regenerate") {
                        Task { try? await profileModel.regenerateHandle() }
                    }
                }
                Button("profile.signOut") { Task { try? await authModel.signOut() } }
                Button("profile.deleteAccount", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
    }

    /// L'e-mail, replié par défaut.
    ///
    /// Le déplier demanderait deux champs de saisie à quelqu'un qui a un
    /// bouton Apple juste au-dessus ; le laisser ouvert en permanence donnerait
    /// à la saisie manuelle le poids visuel du chemin recommandé, ce qu'elle
    /// n'est pas. C'est le troisième choix, présenté comme tel.
    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(showEmailForm ? "profile.signIn.email.hide" : "profile.signIn.email.show") {
                withAnimation { showEmailForm.toggle() }
            }
            .font(NCTypography.body)

            if showEmailForm {
                TextField("profile.signIn.email.address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("profile.signIn.email.password", text: $password)
                    // `.password` et pas `.newPassword` : le même champ sert à
                    // se connecter et à s'inscrire, et `.newPassword` ferait
                    // proposer un mot de passe fort à quelqu'un qui veut
                    // simplement ressaisir le sien.
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)

                if authModel.awaitingEmailConfirmation {
                    Text("profile.signIn.email.confirmationSent")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(NCColor.neonCyan)
                }

                HStack(spacing: 12) {
                    Button("profile.signIn.email.signIn") {
                        Task {
                            do { try await authModel.signIn(email: email, password: password) }
                            catch { reportSignIn(error) }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("profile.signIn.email.signUp") {
                        Task {
                            do { try await authModel.signUp(email: email, password: password) }
                            catch { reportSignIn(error) }
                        }
                    }
                }
                .font(NCTypography.body)
            }
        }
    }

    /// Traduit une erreur de connexion non-Apple en message affichable.
    ///
    /// Les problèmes de saisie sont dits dans la langue de l'utilisateur ; tout
    /// le reste vient du réseau ou de GoTrue, et son texte anglais est ce qui
    /// permet de comprendre le blocage — le masquer par un message générique
    /// rendrait le diagnostic impossible.
    private func reportSignIn(_ error: any Error) {
        let message: String
        switch error as? EmailCredentialProblem {
        case .emptyEmail: message = String(localized: "profile.signIn.email.errorEmpty")
        case .malformedEmail: message = String(localized: "profile.signIn.email.errorMalformed")
        case .passwordTooShort(let minimum):
            message = String(format: String(localized: "profile.signIn.email.errorShort %lld"), minimum)
        case nil:
            // Une annulation est un geste volontaire, pas une panne : refermer
            // la feuille du navigateur ne doit rien afficher.
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return }
            message = error.localizedDescription
        }
        print("SettingsScreen: connexion refusée — \(message)")
        signInError = message
    }

    private func deleteAccount() async {
        guard let userID = authModel.userID else { return }
        if await settingsModel.deleteAccount(uid: userID, serverEnabled: serverFeatures.isEnabled) {
            try? await authModel.signOut()
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
