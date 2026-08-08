import SwiftUI

/// Les chiffres d'un compte à rebours, à la seconde, une colonne par unité.
///
/// Extraits d'`OnlineEventCountdown` le jour où la carte de sortie du fil actu a
/// eu besoin des mêmes. Le découpage, les chiffres à largeur fixe et la bascule
/// d'urgence n'existaient qu'en un exemplaire ; deux copies auraient divergé.
///
/// **Quatre colonnes séparées et non une ligne suivie.** « 102j 2h 35min 47s »
/// se lit comme une durée — quelque chose qu'on parcourt de gauche à droite pour
/// en faire la somme. Une colonne par unité se lit comme un tableau de bord : on
/// y prend le nombre qu'on cherche sans lire le reste, et le trait qui sépare
/// deux colonnes fait le travail que les suffixes faisaient mal.
///
/// Le libellé de l'ensemble n'est PAS ici : c'est la seule chose qui distingue
/// les deux usages — une fenêtre qui se referme n'est pas un jeu qui sort — et
/// c'est donc à l'appelant de le poser.
struct NCCountdownDigits: View {
    let remaining: TimeInterval

    var body: some View {
        // `max(0, …)` : l'appelant décide d'afficher ou non un rebours expiré,
        // mais s'il l'affiche il ne doit jamais voir de chiffres négatifs.
        let total = max(0, Int(remaining))
        let days = total / 86_400

        // Le dernier jour, la rampe cède la place à un magenta PLEIN. Un
        // changement de nature — dégradé contre aplat — se remarque mieux qu'un
        // simple changement de teinte, et il tombe au moment où la colonne des
        // jours disparaît : les deux signaux disent la même chose.
        let isLastDay = days == 0

        // La colonne des jours s'efface plutôt que d'afficher un zéro : trois
        // colonnes plus larges valent mieux qu'une quatrième qui ne dit rien.
        var columns: [(value: Int, label: LocalizedStringKey)] = []
        if !isLastDay { columns.append((days, "countdown.unit.days")) }
        columns.append(((total % 86_400) / 3600, "countdown.unit.hours"))
        columns.append(((total % 3600) / 60, "countdown.unit.minutes"))
        columns.append((total % 60, "countdown.unit.seconds"))

        return HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                if index > 0 { separator }
                unit(
                    column.value,
                    column.label,
                    tint: isLastDay
                        ? NCColor.sunsetMagenta
                        // La rampe est échantillonnée par colonne plutôt que
                        // posée en `LinearGradient` sur chacune : un dégradé par
                        // colonne repartirait de zéro à l'intérieur de chaque
                        // nombre, ce qui donne quatre petits dégradés au lieu
                        // d'un seul qui traverse la ligne.
                        : NCColor.sunsetRamp(Double(index) / Double(columns.count - 1))
                )
            }
        }
        // Pas d'animation implicite sur le battement : SwiftUI ferait fondre
        // chaque seconde dans la suivante, ce qui se lit comme un défaut de
        // rendu.
        .animation(nil, value: total)
    }

    private func unit(_ value: Int, _ labelKey: LocalizedStringKey, tint: Color) -> some View {
        VStack(spacing: 2) {
            // Complété à deux chiffres par le style de format et non par un
            // `String(format:)` : les chiffres restent ceux de la langue de
            // l'appareil.
            Text(value, format: .number.precision(.integerLength(2...)))
                // `monospacedDigit` n'est pas cosmétique : sans lui, chaque
                // seconde change la largeur des chiffres et toute la colonne
                // tremble.
                .font(.system(size: 32, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .ncNeonGlow(tint)

            Text(labelKey)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                // « Secondes », « Sekunden », « Segundos » : la colonne la plus
                // étroite porte le mot le plus long dans presque toutes les
                // langues.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // Colonnes de largeur égale : sans ça, « Jours » et « Secondes »
        // donneraient des colonnes de largeurs différentes, et les chiffres ne
        // seraient plus alignés d'une unité à l'autre.
        .frame(maxWidth: .infinity)
    }

    /// Le trait de séparation. À la hauteur des chiffres seuls, pas de toute la
    /// colonne : descendu jusque sous les libellés, il découperait la ligne de
    /// légende en tronçons.
    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1, height: 30)
            // Compense la hauteur du libellé, que ce trait ne couvre pas, pour
            // rester centré sur les chiffres.
            .padding(.bottom, 14)
    }
}
