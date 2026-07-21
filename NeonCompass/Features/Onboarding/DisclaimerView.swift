import SwiftUI

struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(NCColor.sunset)
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
