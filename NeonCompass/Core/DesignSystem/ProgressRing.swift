import SwiftUI

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
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
            // `verbatim` : un nombre suivi de « % » n'a rien à traduire, mais
            // sans ça SwiftUI en fait une clé de localisation (`%lld%%`) que
            // l'extracteur reverse dans le catalogue comme une souche vide.
            Text(verbatim: "\(Int((progress * 100).rounded()))%")
                .font(NCTypography.displayTitle)
                .foregroundStyle(.white)
        }
    }
}
