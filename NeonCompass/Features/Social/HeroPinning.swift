import SwiftUI

/// Le seuil d'épinglage du rebours. Pur, donc testé ; la valeur se règle à
/// l'œil au simulateur — la spec part de « héro sorti à 92 % ».
enum HeroPinning {
    static let visibleFraction: CGFloat = 0.08

    static func isPinned(heroFrame: CGRect, visibleTop: CGFloat) -> Bool {
        guard heroFrame.height > 0 else { return false }
        let visible = heroFrame.maxY - visibleTop
        return visible < heroFrame.height * visibleFraction
    }
}

/// La capsule de rebours qui remplace le héro sorti de l'écran : le jeu de la
/// page active et le temps restant. « Le rebours est le produit », littéral.
struct PinnedCountdownChip: View {
    let game: Game
    let remaining: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: game.shortLabel)
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.7))
            WeeklyCountdownLabel(remaining: remaining)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
