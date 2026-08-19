import SwiftUI
import AuthenticationServices

/// Feuille de réglages, ouverte depuis l'entête du Profil.
///
/// En feuille et pas en `toolbar` : aucun écran d'onglet n'a de
/// `NavigationStack` — `RootView` les empile dans un `ZStack` sous une barre
/// maison — donc un `ToolbarItem` ne s'afficherait nulle part, sans erreur ni
/// avertissement. Même motif que `PaywallView`.
///
/// En `Form` et plus en `VStack` : sur iOS 26 il apporte Liquid Glass, Dynamic
/// Type, les tailles de frappe et les affordances VoiceOver sans une ligne de
/// code, ce que la pile à plat redéfinissait mal — tout y avait le même poids
/// visuel, badge Pro compris, et « Supprimer mon compte » y voisinait la
/// bascule d'icône. Le corps de cet écran ne porte plus que la structure, les
/// feuilles et les alertes ; chaque section vit dans son fichier.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
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

    init(profileModel: ProfileModel, communityModel: CommunityModel?) {
        self.profileModel = profileModel
        self.communityModel = communityModel
        _settingsModel = State(initialValue: SettingsModel(profileModel: profileModel))
    }

    var body: some View {
        NavigationStack {
            Form {
                SettingsAccountSection(
                    profileModel: profileModel,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    onSignInFailure: reportSignIn,
                    onAppleResult: handleSignInResult,
                    onPrepareAppleRequest: prepareAppleRequest
                )

                proSection

                if proEntitlementModel.isProEntitled {
                    SettingsAppearanceSection()
                    // Les notifications suivies sont envoyées par une Edge
                    // Function : sans elle, l'écran promettrait un service qui
                    // n'arrive jamais.
                    if serverFeatures.isEnabled {
                        SettingsNotificationsSection(store: followedCategoriesStore)
                    }
                }

                if serverFeatures.isEnabled, let communityModel {
                    SettingsCommunitySection(communityModel: communityModel)
                }
            }
            .scrollContentBackground(.hidden)
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
            // GoTrue, et c'est lui qui permet de comprendre le blocage.
            Text(signInError ?? "")
        }
    }

    /// Ne réénumère pas les avantages : `PaywallView` les liste déjà, et deux
    /// listes finiraient par diverger. Cette section dit l'état, et renvoie.
    @ViewBuilder
    private var proSection: some View {
        Section("settings.section.pro") {
            if proEntitlementModel.isProEntitled {
                Label("settings.pro.active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(NCColor.neonCyan)
                Button("settings.pro.seeBenefits") { showPaywall = true }
            } else {
                Button("profile.pro.upgradeButton") { showPaywall = true }
            }
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInCoordinator.makeRawNonce()
        currentNonce = nonce
        request.requestedScopes = []
        request.nonce = AppleSignInCoordinator.sha256(nonce)
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

    /// Chaque échec est dit. Une version antérieure les avalait tous —
    /// `guard … else { return }` puis `try?` — donc un utilisateur bloqué
    /// n'avait aucun moyen de savoir pourquoi, et nous non plus. C'est la seule
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
        print("SettingsScreen: connexion refusée — \(message)")
        signInError = message
    }
}
