import SwiftUI

/// Les chiffres d'un compte à rebours, à la seconde.
///
/// Extraits d'`OnlineEventCountdown` le jour où la carte de sortie du fil actu a
/// eu besoin des mêmes. Le découpage, l'astuce des chiffres à largeur fixe et la
/// bascule au magenta n'existaient qu'en un exemplaire ; deux copies auraient
/// divergé.
///
/// Le libellé n'est PAS ici : c'est la seule chose qui distingue les deux
/// usages — une fenêtre qui se referme n'est pas un jeu qui sort — et c'est donc
/// à l'appelant de le poser.
struct NCCountdownDigits: View {
    let remaining: TimeInterval

    var body: some View {
        // `max(0, …)` : l'appelant décide d'afficher ou non un rebours expiré,
        // mais s'il l'affiche il ne doit jamais voir de chiffres négatifs.
        let total = max(0, Int(remaining))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        // Le dernier jour, l'enseigne passe au magenta : l'urgence se lit sans
        // avoir à déchiffrer les chiffres.
        let tint = days == 0 ? NCColor.sunsetMagenta : NCColor.neonCyan

        Text(
            days > 0
                ? "countdown.long \(days) \(hours) \(minutes) \(seconds)"
                : "countdown.short \(hours) \(minutes) \(seconds)"
        )
        // `monospacedDigit` n'est pas cosmétique : sans lui, chaque seconde
        // change la largeur des chiffres et toute la ligne tremble.
        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
        .foregroundStyle(tint)
        .ncNeonGlow(tint)
        // Pas d'animation implicite sur le battement : SwiftUI ferait fondre
        // chaque seconde dans la suivante, ce qui se lit comme un défaut de
        // rendu.
        .animation(nil, value: seconds)
    }
}
