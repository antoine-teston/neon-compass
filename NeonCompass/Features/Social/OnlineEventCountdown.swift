import SwiftUI

/// Le compte à rebours d'une fenêtre en ligne, en direct, à la seconde.
///
/// C'est le produit — un article raconte la semaine, personne ne prévient qu'elle
/// se termine demain. Il mérite donc d'être la SEULE chose lumineuse de la carte :
/// la contrainte de design du projet plafonne le halo à trois accents par écran,
/// et en dépenser un ici est le meilleur usage possible.
///
/// `TimelineView(.periodic(by: 1))` plutôt que la minuterie de `SocialScreen`, qui
/// bat à la minute : l'écran n'a pas besoin de se reconstruire chaque seconde,
/// seul ce bloc en a besoin. La minuterie de l'écran reste utile pour faire
/// basculer l'événement courant à l'expiration de la fenêtre.
///
/// Les chiffres eux-mêmes vivent dans `NCCountdownDigits`, partagés avec le
/// rebours de sortie du fil actu.
struct OnlineEventCountdown: View {
    let endsAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = endsAt.timeIntervalSince(context.date)
            VStack(alignment: .leading, spacing: 4) {
                Text("social.event.countdown.title")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
                if remaining > 0 {
                    NCCountdownDigits(remaining: remaining)
                } else {
                    Text("social.event.over")
                        .font(NCTypography.cardTitle)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}
