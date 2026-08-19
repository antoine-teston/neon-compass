import SwiftUI

struct ProgressRing: View {
    /// `nil` quand le total attendu est inconnu : l'anneau ne trace alors aucun
    /// arc et affiche un tiret.
    ///
    /// Optionnel plutôt que zéro, délibérément. Zéro dirait « tu n'as rien
    /// trouvé » là où la vérité est « on ne sait pas encore combien il y en a » —
    /// c'est l'état prévu du volet à venir, dont personne ne connaîtra les
    /// totaux avant plusieurs semaines. `ChallengeProgress.fraction` et
    /// `ChallengeProgressCalculator.overall` rendent déjà `nil` dans ce cas ;
    /// l'anneau était le seul endroit où l'information se perdait.
    let progress: Double?
    var lineWidth: CGFloat = 10
    /// Le chiffre du centre. À dimensionner avec l'anneau : `displayTitle` tient
    /// dans 140 pt et débordait des deux anneaux de 92 pt de la Découverte.
    var font: Font = NCTypography.displayTitle

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    // Le dégradé de marque plutôt qu'un cyan uni : c'est l'élément
                    // héros du Profil, et il était l'un des rares endroits assez
                    // grands pour qu'un dégradé se lise. Le halo, lui, doit rester
                    // une couleur unique — une ombre ne prend pas de `ShapeStyle` —
                    // et prend le violet, milieu de la rampe.
                    .stroke(NCColor.sunset, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: NCColor.sunsetViolet.opacity(0.6), radius: 6)
            }
            // `verbatim` : un nombre suivi de « % » n'a rien à traduire, mais
            // sans ça SwiftUI en fait une clé de localisation (`%lld%%`) que
            // l'extracteur reverse dans le catalogue comme une souche vide. Le
            // tiret cadratin est dans le même cas : c'est un signe, pas un mot.
            Text(verbatim: progress.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .font(font)
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .animation(.snappy(duration: 0.3), value: progress)
    }
}
