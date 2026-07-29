import SwiftUI

struct CheatCard: View {
    let cheat: Cheat
    /// Le code du mode actif, résolu par l'appelant. La carte n'a pas à
    /// connaître le mode : elle affiche le code qu'on lui donne.
    let code: CheatCode
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    // Le badge `blocksTrophies` a quitté la carte : aucun code de GTA V
    // n'empêche le 100 %, il ne se serait jamais déclenché. L'information utile
    // est l'inverse, et elle vit une seule fois en pied de liste.
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(cheat.effect.resolved(for: currentLanguageCode))
                        .font(NCTypography.body.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? NCColor.sunsetOrange : .secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isFavorite ? Text("cheats.favorite.remove") : Text("cheats.favorite.add")
                    )
                }

                CheatCodeView(code: code, glyphSize: 18)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
