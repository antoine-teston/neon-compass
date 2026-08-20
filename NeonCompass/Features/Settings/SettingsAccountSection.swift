import SwiftUI

/// La section Compte : qui on est — en une carte d'identité et non en trois
/// lignes de même poids — et les deux gestes qui mettent fin à la session.
///
/// Déconnecté, elle ne propose plus de se connecter SUR PLACE : Apple, Google et
/// le repli e-mail sont partis dans `SignInSheet`, et il ne reste ici que
/// l'appel qui l'ouvre. Une section de réglages n'est pas l'endroit où l'on
/// choisit un fournisseur d'identité.
struct SettingsAccountSection: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @Environment(ProEntitlementModel.self) private var proEntitlementModel

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

    private var signedInSection: some View {
        Section("settings.section.account") {
            identityCard
        }
    }

    /// La carte d'identité : le pseudo, ce qui se paie, et avec quel compte.
    ///
    /// Elle AFFICHE et ne propose rien. Le pseudo est attribué une fois pour
    /// toutes à la création du compte : lui donner ici un bouton laisserait
    /// croire l'inverse. Trois lignes de même poids — fournisseur, adresse,
    /// pseudo — ne disaient pas laquelle nomme la personne ; celle-ci le dit
    /// par la taille et la couleur, et range le reste en sous-titre.
    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                handleText
                if proEntitlementModel.isProEntitled {
                    // Même capsule que l'entête du Profil, au caractère près :
                    // deux insignes Pro de dessins différents dans la même app
                    // se liraient comme deux états différents.
                    Text("profile.pro.badge")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(NCColor.nightSky)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NCColor.sunset, in: .capsule)
                }
                Spacer()
            }

            if let accountLine {
                Text(accountLine)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    /// Les trois mêmes états que l'entête du Profil, et pour la même raison —
    /// voir `ProfileHeaderState.Title` : sans le gabarit, un connecté verrait
    /// « Ton profil » clignoter avant son pseudo.
    ///
    /// Le pseudo suit `profile != nil`, jamais `serverFeatures` : le lire est un
    /// simple `select` sur sa propre ligne, qui marche même quand les Edge
    /// Functions ne sont pas déployées.
    @ViewBuilder
    private var handleText: some View {
        if let handle = profileModel.profile?.handle {
            styledHandle(Text(handle))
        } else if profileModel.isLoadingProfile {
            styledHandle(Text(verbatim: "NEON-XXXXXX-00"))
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        } else {
            styledHandle(Text("profile.header.anonymous"))
        }
    }

    /// `minimumScaleFactor` pour la même raison que l'entête du Profil : au pire
    /// `generate_handle()` produit 24 caractères, qui passeraient sur deux
    /// lignes et pousseraient la capsule Pro hors de la première.
    private func styledHandle(_ text: Text) -> some View {
        text
            .font(NCTypography.displayTitle)
            .foregroundStyle(NCColor.neonCyan)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// Fournisseur et adresse sur une seule ligne, composée de fragments déjà
    /// traduits — l'adresse est absente pour un compte Apple à relais masqué,
    /// et deux lignes séparées faisaient deux arrêts VoiceOver pour une seule
    /// information.
    ///
    /// `NSLocalizedString` et non `String(localized:)` : la clé du fournisseur
    /// est calculée à l'exécution, et `String(localized:)` veut un littéral.
    private var accountLine: String? {
        guard let account = authModel.currentAccount else { return nil }
        var parts = [NSLocalizedString(account.provider.labelKey, comment: "")]
        if let email = account.email, !email.isEmpty { parts.append(email) }
        return parts.joined(separator: " · ")
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
