import SwiftUI
import AuthenticationServices

/// La section Compte : qui on est, et les deux gestes qui mettent fin à la
/// session.
///
/// Les boutons de connexion sont DÉPLACÉS depuis `SettingsScreen` sans changer
/// d'une ligne — le protocole Sign in with Apple n'est pas retouché pendant une
/// refonte de mise en page.
struct SettingsAccountSection: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures

    let profileModel: ProfileModel
    @Binding var showDeleteConfirmation: Bool
    @Binding var showHandleConfirmation: Bool
    let onSignInFailure: (any Error) -> Void
    let onAppleResult: (Result<ASAuthorization, Error>) -> Void
    let onPrepareAppleRequest: (ASAuthorizationAppleIDRequest) -> Void

    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        if authModel.userID == nil {
            signedOutSection
        } else {
            signedInSection
            destructiveSection
        }
    }

    // MARK: - Connecté

    @ViewBuilder
    private var signedInSection: some View {
        Section("settings.section.account") {
            if let account = authModel.currentAccount {
                Text(LocalizedStringKey(account.provider.labelKey))
                if let email = account.email, !email.isEmpty {
                    Text(email)
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if serverFeatures.isEnabled {
                if let handle = profileModel.profile?.handle {
                    LabeledContent("settings.account.handle") { Text(handle) }
                }
                Button("profile.handle.regenerate") { showHandleConfirmation = true }
            }
        }
    }

    /// « Supprimer mon compte » cesse de cohabiter avec le reste : sa propre
    /// section, sans titre, tout en bas.
    private var destructiveSection: some View {
        Section {
            Button("profile.signOut") { Task { try? await authModel.signOut() } }
            Button("profile.deleteAccount", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Déconnecté

    private var signedOutSection: some View {
        Section("settings.section.account") {
            Text(serverFeatures.isEnabled ? "profile.signIn.prompt" : "profile.signIn.syncOnlyPrompt")
                .font(NCTypography.body)

            // Apple en premier, et en tête : la règle App Store 4.8 l'exige dès
            // qu'un autre fournisseur tiers est proposé.
            SignInWithAppleButton(.signIn) { request in
                onPrepareAppleRequest(request)
            } onCompletion: { result in
                onAppleResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)

            Button("profile.signIn.google") {
                Task {
                    do { try await authModel.signInWithGoogle() } catch { onSignInFailure(error) }
                }
            }

            // L'e-mail replié par défaut : le déplier demanderait deux champs de
            // saisie à quelqu'un qui a un bouton Apple juste au-dessus. C'est le
            // troisième choix, présenté comme tel.
            Button(showEmailForm ? "profile.signIn.email.hide" : "profile.signIn.email.show") {
                withAnimation { showEmailForm.toggle() }
            }

            if showEmailForm { emailRows }
        }
    }

    @ViewBuilder
    private var emailRows: some View {
        TextField("profile.signIn.email.address", text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        // `.password` et pas `.newPassword` : le même champ sert à se connecter
        // et à s'inscrire, et `.newPassword` ferait proposer un mot de passe
        // fort à quelqu'un qui veut simplement ressaisir le sien.
        SecureField("profile.signIn.email.password", text: $password)
            .textContentType(.password)

        if authModel.awaitingEmailConfirmation {
            Text("profile.signIn.email.confirmationSent")
                .font(NCTypography.cardMeta)
                .foregroundStyle(NCColor.neonCyan)
        }

        Button("profile.signIn.email.signIn") {
            Task {
                do { try await authModel.signIn(email: email, password: password) }
                catch { onSignInFailure(error) }
            }
        }

        Button("profile.signIn.email.signUp") {
            Task {
                do { try await authModel.signUp(email: email, password: password) }
                catch { onSignInFailure(error) }
            }
        }
    }
}
