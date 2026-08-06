import SwiftUI

/// Dit le geste avant d'envoyer sur la carte.
///
/// Une contribution SE POSE sur la carte : `ContributionPlacement` exige une
/// `position`, et le seul chemin est l'appui long (`MapScreen`). Basculer
/// directement sur l'onglet Carte laisserait l'utilisateur devant un écran sans
/// indice sur ce qu'on attend de lui.
///
/// **Deux appelants, d'où sa place ici et non dans `Features/Profile`** : la
/// ligne d'invitation du profil, et le CTA du volet Propositions. Même
/// précédent que `SignInToContributeAlert`, partagée entre la carte et Social —
/// ce qui sert deux features vit dans `Community`.
struct ContributeHintSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onOpenMap: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 44))
                    .foregroundStyle(NCColor.neonCyan)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Text("profile.contribute.hint.message")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Button {
                    onOpenMap()
                    dismiss()
                } label: {
                    Text("profile.contribute.hint.openMap")
                        .font(NCTypography.body.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(NCColor.neonCyan)

                Button("profile.contribute.hint.cancel") { dismiss() }
                    .font(NCTypography.body)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(NCColor.nightSky.ignoresSafeArea())
            .navigationTitle("profile.contribute.hint.title")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
