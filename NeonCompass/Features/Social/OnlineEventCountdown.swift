import SwiftUI

/// Le compte à rebours, en direct, à la seconde.
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
                    digits(for: remaining)
                } else {
                    Text("social.event.over")
                        .font(NCTypography.cardTitle)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    /// `monospacedDigit` n'est pas cosmétique : sans lui, chaque seconde change la
    /// largeur des chiffres et toute la ligne tremble.
    @ViewBuilder
    private func digits(for remaining: TimeInterval) -> some View {
        let total = Int(remaining)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        // Le dernier jour, l'enseigne passe au magenta : l'urgence se lit sans
        // avoir à déchiffrer les chiffres.
        let tint = days == 0 ? NCColor.sunsetMagenta : NCColor.neonCyan

        Text(
            days > 0
                ? "social.event.countdown.long \(days) \(hours) \(minutes) \(seconds)"
                : "social.event.countdown.short \(hours) \(minutes) \(seconds)"
        )
        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
        .foregroundStyle(tint)
        // Deux ombres et non une : un seul rayon donne un flou plat, deux rayons
        // donnent le cœur net et l'auréole large d'une enseigne.
        .shadow(color: tint.opacity(0.9), radius: 4)
        .shadow(color: tint.opacity(0.5), radius: 14)
        // Pas d'animation implicite sur le battement : SwiftUI ferait fondre
        // chaque seconde dans la suivante, ce qui se lit comme un défaut de rendu.
        .animation(nil, value: seconds)
    }
}
