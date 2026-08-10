import ActivityKit
import SwiftUI
import WidgetKit

/// Les favoris sur l'écran verrouillé et dans l'île.
///
/// **Cinq lignes dans environ cent cinquante-sept points**, en-tête compris. Soit
/// vingt-quatre points par favori : de quoi tenir UNE ligne, pas deux. C'est la
/// contrainte qui dicte tout ici — le code gros et prioritaire, l'effet réduit à
/// un rappel qui cède la place, aucune icône, aucun verre.
///
/// Un code se lit à bout de bras, une manette dans les mains. La lisibilité prime
/// sur la parenté visuelle avec l'app, et elle prime aussi sur l'envie de tout
/// montrer.
struct FavoritesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FavoritesActivityAttributes.self) { context in
            lockScreen(context.attributes, context.state)
                // Le fond de la bannière, pas celui de l'app : l'écran
                // verrouillé impose déjà son propre matériau au-dessus.
                .activityBackgroundTint(NCColor.nightSky)
                .activitySystemActionForegroundColor(NCColor.sunsetOrange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(NCColor.sunsetOrange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.modeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Trois et non cinq : l'île déployée est plus basse que la
                    // bannière, et cinq lignes y deviennent illisibles.
                    rows(Array(context.state.entries.prefix(3)))
                }
            } compactLeading: {
                Image(systemName: "star.fill")
                    .foregroundStyle(NCColor.sunsetOrange)
            } compactTrailing: {
                Text(verbatim: "\(context.state.entries.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(NCColor.sunsetOrange)
            } minimal: {
                Image(systemName: "star.fill")
                    .foregroundStyle(NCColor.sunsetOrange)
            }
        }
    }

    private func lockScreen(
        _ attributes: FavoritesActivityAttributes,
        _ state: FavoritesActivityAttributes.ContentState
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("cheats.favorites.title")
                    .textCase(.uppercase)
                Spacer()
                // Le jeu ET le mode : sans eux, une suite de glyphes ne dit pas
                // de quelle manette ni de quel jeu elle parle.
                Text(verbatim: "\(attributes.gameLabel) · \(state.modeLabel)")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(NCColor.sunsetOrange)

            rows(state.entries)
        }
        .padding(12)
    }

    /// UNE ligne par favori, et le code prioritaire.
    ///
    /// **C'est une correction, pas un choix initial.** La première version
    /// empilait l'effet au-dessus du code, deux lignes par favori. La bannière
    /// fait environ cent cinquante-sept points, l'en-tête en prend quatorze : il
    /// reste vingt-quatre points par favori, où deux lignes de texte ne tiennent
    /// qu'en devenant minuscules. Le résultat était illisible — et c'est le
    /// contraire de ce que cette activité existe pour faire.
    ///
    /// Sur une seule ligne, le code monte à seize points. L'effet passe en
    /// second : il se coupe, et disparaît même complètement devant un code de
    /// douze boutons. C'est le bon arbitrage — on vient lire le CODE ; l'effet
    /// rappelle seulement lequel c'est.
    private func rows(_ entries: [FavoritesActivityAttributes.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.effect)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // Le seul élément dont la largeur soit négociable. Sans
                        // cette priorité, un code long se ferait couper à sa
                        // place — et un code coupé ne vaut rien.
                        .layoutPriority(-1)
                    Spacer(minLength: 6)
                    if let code = entry.code {
                        Text(code)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(NCColor.neonCyan)
                            .lineLimit(1)
                            // Il rétrécit plutôt que de se couper : mieux vaut un
                            // code un peu petit qu'un code amputé.
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("cheats.favorites.noCodeHere")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
