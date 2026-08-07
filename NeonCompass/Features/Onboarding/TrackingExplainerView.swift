import SwiftUI

/// L'explication qui précède la boîte système d'Apple.
///
/// **Pourquoi un écran maison plutôt que le message ATT hébergé par Google.**
/// Le message de la console Privacy & messaging éviterait ce fichier et serait
/// modifiable sans mise à jour de l'app — mais il s'affiche pendant le flux de
/// consentement, au premier lancement. Les deux options s'excluent, et celle qui
/// porte le gain d'opt-in est celle qui attend la deuxième session.
///
/// Le texte reste neutre et ne promet rien : une pré-demande qui incite, ou qui
/// laisse croire que la boîte système est autre chose qu'elle-même, est un motif
/// de rejet. « Plus tard » n'est pas un refus — il repousse au prochain
/// lancement, et l'utilisateur garde le dernier mot dans la boîte d'Apple.
struct TrackingExplainerView: View {
    let onContinue: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 52))
                .foregroundStyle(NCColor.neonCyan)
                .accessibilityHidden(true)

            Text("att.explainer.title")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("att.explainer.body")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button(action: onContinue) {
                    Text("att.explainer.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("att.explainer.later", action: onLater)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .presentationDetents([.medium])
    }
}
