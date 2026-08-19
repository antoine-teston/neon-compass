import SwiftUI

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
///
/// La connexion n'y est plus : elle a sa propre feuille (`SignInSheet`), et les
/// réglages n'en gardent que l'appel. Rien ici ne parle plus à Apple, Google ou
/// GoTrue.
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
    /// Présentée d'ici et non par `RootView`, qui porte pourtant la même
    /// feuille : une vue ne présente qu'UNE feuille à la fois, et lever
    /// `AppModel.showsSignIn` pendant que les réglages sont à l'écran ne montre
    /// rien du tout — mesuré au simulateur le 2026-08-19. Le paywall juste à
    /// côté suit la même règle depuis toujours.
    @State private var showSignIn = false

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
                    showSignIn: $showSignIn
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
        .sheet(isPresented: $showSignIn) { SignInSheet() }
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
    }

    /// Ne réénumère pas les avantages : `PaywallView` les liste déjà, et deux
    /// listes finiraient par diverger. Cette section dit l'état, et renvoie.
    @ViewBuilder
    private var proSection: some View {
        Section {
            if proEntitlementModel.isProEntitled {
                Label("settings.pro.active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(NCColor.neonCyan)
                Button("settings.pro.seeBenefits") { showPaywall = true }
            } else {
                Button("profile.pro.upgradeButton") { showPaywall = true }
            }
        } header: {
            SettingsIconLabel(
                "settings.section.pro",
                systemImage: "crown.fill",
                tint: NCColor.sunset
            )
        }
    }

    private func deleteAccount() async {
        guard let userID = authModel.userID else { return }
        if await settingsModel.deleteAccount(uid: userID, serverEnabled: serverFeatures.isEnabled) {
            try? await authModel.signOut()
        }
    }
}
