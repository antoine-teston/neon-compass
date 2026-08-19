import SwiftUI
import AuthenticationServices

/// La connexion, en feuille et à elle seule.
///
/// Elle vivait au bas d'une section des réglages, entre une bascule d'icône et
/// une liste de contributeurs bloqués : le bouton Apple, le bouton Google et le
/// repli e-mail y avaient exactement le même poids visuel qu'une préférence.
/// Ici, l'écran ne dit qu'une chose — et son pied de feuille dit ce que la
/// connexion ne conditionne PAS, parce que parcourir l'app n'a jamais demandé
/// de compte.
///
/// Présentée par `RootView` et non par un écran : les trois chemins qui y mènent
/// — l'invitation du Profil, l'alerte de contribution, l'appel des réglages —
/// vivent dans trois sous-arbres qui n'ont en commun que `AppModel`.
///
/// Toute la plomberie Sign in with Apple vient de `SettingsScreen` SANS
/// retouche : le protocole n'est pas réécrit pendant un déménagement.
struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var authModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @Environment(ThemeStore.self) private var themeStore

    @State private var currentNonce: String?
    @State private var signInError: String?
    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NCColor.nightSky.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    providers
                    if showEmailForm { emailForm }
                    footer
                }
                // Bornée puis recentrée : sur l'iPad, des boutons pleine largeur
                // traverseraient toute la feuille.
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding(24)
                .padding(.top, 24)
            }
            closeButton
        }
        // La teinte vit ICI et pas chez le présentateur : un `.tint` posé
        // au-dessus d'un `.sheet` ne franchit jamais la feuille (motif
        // documenté RootView.swift:91-94), et cette feuille a trois
        // présentateurs — la porter elle-même est le seul moyen que les
        // trois chemins restent d'accord.
        .tint(themeStore.selectedTheme.accent)
        .presentationDragIndicator(.visible)
        // La feuille a dit tout ce qu'elle avait à dire dès que le compte
        // existe. La laisser ouverte obligerait à la refermer à la main pour
        // voir ce qu'on était venu y chercher.
        .onChange(of: authModel.userID) { _, userID in
            if userID != nil { dismiss() }
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

    // MARK: - Entête

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(NCColor.neonCyan)
                .accessibilityHidden(true)

            // Nom propre, donc `verbatim` et jamais le catalogue : cinq copies
            // identiques d'un mot qui ne se traduit pas. Même règle que
            // `NCWordmark`, qui l'explique en entier.
            Text(verbatim: "Neon Compass")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)

            Text(serverFeatures.isEnabled ? "profile.signIn.prompt" : "profile.signIn.syncOnlyPrompt")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    private var closeButton: some View {
        Button("signIn.close", systemImage: "xmark.circle.fill") { dismiss() }
            .labelStyle(.iconOnly)
            .font(.system(size: 26))
            .foregroundStyle(.white.opacity(0.45))
            .padding(20)
    }

    // MARK: - Fournisseurs

    @ViewBuilder
    private var providers: some View {
        // Apple en premier, et en tête : la règle App Store 4.8 l'exige dès
        // qu'un autre fournisseur tiers est proposé.
        SignInWithAppleButton(.signIn) { request in
            prepareAppleRequest(request)
        } onCompletion: { result in
            handleSignInResult(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)

        Button {
            Task {
                do { try await authModel.signInWithGoogle() } catch { reportSignIn(error) }
            }
        } label: {
            Text("profile.signIn.google")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.glass)

        // L'e-mail replié par défaut : le déplier demanderait deux champs de
        // saisie à quelqu'un qui a un bouton Apple juste au-dessus. C'est le
        // troisième choix, présenté comme tel.
        Button(showEmailForm ? "profile.signIn.email.hide" : "profile.signIn.email.show") {
            withAnimation { showEmailForm.toggle() }
        }
        .font(NCTypography.body)
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("profile.signIn.email.address", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))

            // `.password` et pas `.newPassword` : le même champ sert à se connecter
            // et à s'inscrire, et `.newPassword` ferait proposer un mot de passe
            // fort à quelqu'un qui veut simplement ressaisir le sien.
            SecureField("profile.signIn.email.password", text: $password)
                .textContentType(.password)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))

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
                .frame(maxWidth: .infinity)

                Button("profile.signIn.email.signUp") {
                    Task {
                        do { try await authModel.signUp(email: email, password: password) }
                        catch { reportSignIn(error) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .font(NCTypography.body)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// Ce que la connexion ne conditionne pas. Une feuille qui s'ouvre d'elle-
    /// même sur un geste refusé ressemble à un péage : cette ligne dit qu'il n'y
    /// en a pas, et à quoi sert le compte quand on en veut un.
    private var footer: some View {
        Text("signIn.footer")
            .font(NCTypography.cardMeta)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Plomberie de connexion

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
        print("SignInSheet: connexion refusée — \(message)")
        signInError = message
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
        print("SignInSheet: connexion refusée — \(message)")
        signInError = message
    }
}
