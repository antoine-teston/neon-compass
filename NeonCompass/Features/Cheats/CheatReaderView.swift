import SwiftUI

/// Le mode « manette en main » : un seul code, aussi gros que possible, et
/// l'écran qui ne s'éteint pas pendant qu'on le saisit.
struct CheatReaderView: View {
    let cheats: [Cheat]
    let inputMode: CheatInputMode
    let onDismiss: () -> Void

    @State private var currentIndex: Int

    init(cheats: [Cheat], startIndex: Int, inputMode: CheatInputMode, onDismiss: @escaping () -> Void) {
        self.cheats = cheats
        self.inputMode = inputMode
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: startIndex)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Text(cheats[currentIndex].effect.resolved(for: currentLanguageCode))
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let code = cheats[currentIndex].codes[inputMode] {
                    // Centré, comme le titre au-dessus : le lecteur affichait un
                    // titre centré surmontant un code collé au bord gauche.
                    CheatCodeView(code: code, glyphSize: 44, alignment: .center)
                        .frame(maxWidth: .infinity)
                }

                Button("cheats.reader.close", action: onDismiss)
                    .buttonStyle(.glassProminent)
                    .tint(NCColor.sunsetMagenta)
            }
            .padding(32)
        }
        // Le geste reste tel quel, avec ses défauts : ni suivi du doigt, ni
        // rebond en butée, ni indicateur de position, et il intercepte les
        // balayages d'accessibilité. C'est antérieur aux quatre modes de saisie,
        // et le corriger ici serait un refactor d'opportunité.
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
}
