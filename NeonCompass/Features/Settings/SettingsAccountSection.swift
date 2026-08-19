import SwiftUI

/// La section Compte : qui on est, et les deux gestes qui mettent fin à la
/// session.
///
/// Déconnecté, elle ne propose plus de se connecter SUR PLACE : Apple, Google et
/// le repli e-mail sont partis dans `SignInSheet`, et il ne reste ici que
/// l'appel qui l'ouvre. Une section de réglages n'est pas l'endroit où l'on
/// choisit un fournisseur d'identité.
struct SettingsAccountSection: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures

    let profileModel: ProfileModel
    @Binding var showDeleteConfirmation: Bool
    /// La feuille est présentée par `SettingsScreen`, qui explique pourquoi ce
    /// n'est pas `AppModel.showsSignIn` qui l'ouvre d'ici.
    @Binding var showSignIn: Bool

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

            // Le pseudo suit `profile != nil`, comme l'entête : le lire est un
            // simple `select` sur sa propre ligne, qui marche même quand les
            // Edge Functions ne sont pas déployées. Le garder derrière
            // `serverFeatures` affichait le pseudo en haut du Profil et le
            // cachait ici, sur le même appareil et à la même seconde.
            if let handle = profileModel.profile?.handle {
                LabeledContent("settings.account.handle") { Text(handle) }
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

            Button { showSignIn = true } label: {
                Text("profile.signIn.open")
                    .font(NCTypography.body.bold())
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(NCColor.neonCyan)
            .foregroundStyle(NCColor.nightSky)
        }
    }
}
