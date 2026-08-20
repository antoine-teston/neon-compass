import SwiftUI

struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                // Premier écran vu de l'app : c'est ici que le ton se donne, et
                // il se donnait avec un symbole système. Le repli garde ce
                // symbole tant que l'illustration n'est pas déposée — un écran
                // qui avait déjà quelque chose à cet endroit ne doit pas perdre
                // ce quelque chose en attendant mieux.
                NCArtworkBanner(artwork: .disclaimer, height: 140) {
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(NCColor.sunset)
                }
                .padding(.horizontal, 24)
                Text("disclaimer.title")
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                Text("disclaimer.body")
                    .font(NCTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Button("disclaimer.accept", action: onAccept)
                    .buttonStyle(.glassProminent)
                    .tint(NCColor.sunsetMagenta)
                    .padding(.bottom, 40)
            }
        }
    }
}
