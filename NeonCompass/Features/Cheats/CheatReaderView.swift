import SwiftUI

struct CheatReaderView: View {
    let cheats: [Cheat]
    let platform: Platform
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(cheats: [Cheat], startIndex: Int, platform: Platform, onDismiss: @escaping () -> Void) {
        self.cheats = cheats
        self.platform = platform
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Text(cheats[currentIndex].effect.en)
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                glyphRows

                Button("cheats.reader.close", action: onDismiss)
                    .buttonStyle(.glassProminent)
                    .tint(NCColor.sunsetMagenta)
            }
            .padding(32)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < 0, currentIndex < cheats.count - 1 {
                        currentIndex += 1
                    } else if value.translation.width > 0, currentIndex > 0 {
                        currentIndex -= 1
                    }
                }
        )
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var glyphRows: some View {
        let sequence = cheats[currentIndex].sequence[platform] ?? []
        return HStack(spacing: 24) {
            ForEach(Array(sequence.enumerated()), id: \.offset) { _, button in
                Image(systemName: GamepadGlyph.systemImage(for: button, platform: platform))
                    .font(.system(size: 64))
                    .foregroundStyle(NCColor.neonCyan)
            }
        }
    }
}
