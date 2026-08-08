import SwiftUI

/// La rose des vents du mot-marque.
///
/// Un tracé à nous et non un SF Symbol : le seul glyphe système qui ressemble
/// vraiment à une boussole est celui de Safari, et emprunter l'icône d'une autre
/// app pour porter notre identité serait un mauvais calcul. La contrainte IP du
/// projet dit la même chose autrement — ce qui nous identifie doit être
/// original.
///
/// Quatre branches et non huit : à seize points de côté, huit branches se
/// referment en tache. Le creux entre deux branches est à 30 % du rayon, ce qui
/// donne l'étoile effilée des roses de carte marine plutôt qu'un losange épais.
struct NCCompassRose: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.3

        var path = Path()
        // Huit sommets alternés — pointe, creux, pointe… — en partant du nord,
        // d'où le décalage d'un quart de tour.
        for step in 0..<8 {
            let angle = (Double(step) * 45 - 90) * .pi / 180
            let radius = step.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Le mot-marque de l'app : la rose, puis le nom.
///
/// Le nom passe par `Text(verbatim:)` et NON par le catalogue de chaînes. C'est
/// délibéré et c'est l'exception à la règle « aucun littéral en dur » de
/// `CLAUDE.md` : un nom propre ne se traduit pas, et l'inscrire au catalogue
/// obligerait `LocalizationCoverageTests` à garder cinq copies identiques d'un
/// mot qui ne changera jamais.
struct NCWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            NCCompassRose()
                .fill(NCColor.neonCyan)
                .frame(width: 16, height: 16)
                // Une seule ombre, et courte. La barre est présente sur quatre
                // écrans sur cinq : elle ne peut pas dépenser un des trois
                // accents lumineux que `CLAUDE.md` autorise par écran, sans quoi
                // il n'en resterait que deux partout.
                .shadow(color: NCColor.neonCyan.opacity(0.55), radius: 5)

            Text(verbatim: "NEON COMPASS")
                .font(.system(size: 13, weight: .black, design: .rounded))
                // L'interlettrage large est ce qui distingue un mot-marque d'un
                // titre d'écran : sans lui, la barre se lit comme un en-tête de
                // liste.
                .tracking(2)
                .foregroundStyle(.white.opacity(0.9))
        }
        // Sans quoi VoiceOver annonce la rose comme une image sans nom, puis le
        // texte en capitales lettre par lettre.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Neon Compass"))
    }
}
