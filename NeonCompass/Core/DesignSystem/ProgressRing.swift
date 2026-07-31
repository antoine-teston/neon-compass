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
                .stroke(NCColor.neonCyan, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: NCColor.neonCyan.opacity(0.6), radius: 6)
            // `verbatim` : un nombre suivi de « % » n'a rien à traduire, mais
            // sans ça SwiftUI en fait une clé de localisation (`%lld%%`) que
            // l'extracteur reverse dans le catalogue comme une souche vide.
            Text(verbatim: "\(Int((progress * 100).rounded()))%")
                .font(NCTypography.displayTitle)
                .foregroundStyle(.white)
        }
    }
}
