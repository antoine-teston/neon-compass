import SwiftUI

/// La carte Découverte : deux anneaux, les deux jeux, toujours.
///
/// Remplace les cartes par jeu de `ProgressionListView`, qui empilaient un
/// anneau de 140 pt et une ligne par collection — quinze lignes pour la carte de
/// référence, soit ~1 100 pt dans un `ScrollView` déjà long — et qui filtraient
/// les jeux sans défi, ce qui rendait le volet à venir purement invisible.
///
/// Le détail part en feuille plutôt que dans un dépliage : un dépliage ramène la
/// hauteur d'un coup et son état se perd à chaque bascule d'onglet, là où une
/// feuille peut porter son propre `NavigationStack` — donc un titre et une
/// fermeture, qu'un écran d'onglet ne sait pas afficher.
struct DiscoveryCard: View {
    let state: DiscoveryState
    let onOpenChallenges: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("profile.discovery.title")
                .font(NCTypography.cardTitle)
                .foregroundStyle(.white)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 12) {
                ForEach(state.games) { game in
                    gameColumn(game)
                }
            }
            .frame(maxWidth: .infinity)

            if state.challengeCount > 0 {
                Divider().overlay(Color.white.opacity(0.08))
                challengesButton
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func gameColumn(_ game: DiscoveryGameState) -> some View {
        VStack(spacing: 8) {
            ProgressRing(progress: game.progress, lineWidth: 8, font: NCTypography.featuredTitle)
                .frame(width: 92, height: 92)

            // Chiffres romains nus, jamais la marque : CLAUDE.md interdit les
            // marques déposées dans la prose de l'app. `verbatim` parce que « V »
            // et « VI » sont identiques dans les cinq langues — c'est même ce qui
            // en fait des noms et non des phrases.
            Text(verbatim: game.game.shortLabel)
                .font(NCTypography.cardTitle)
                .foregroundStyle(NCColor.neonCyan)
                .breathingHighlight(game.game == .leonida)

            Text(tally(game))
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(game.foundCount)))
                .animation(.snappy(duration: 0.2), value: game.foundCount)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// « 137 / 267 » quand le total est connu, « 12 lieux » sinon. Même règle que
    /// les lignes de défi de la feuille, et pour la même raison : un total
    /// inventé serait faux, un compte absolu reste juste.
    ///
    /// Le numérateur est `foundInChallenges` et non `foundCount` : c'est le seul
    /// qui compte la même population que le dénominateur, donc le seul qui
    /// puisse être posé sur la même barre de fraction — et le seul dont le
    /// quotient soit le pourcentage que l'anneau affiche juste au-dessus.
    private func tally(_ game: DiscoveryGameState) -> String {
        guard let expected = game.expectedCount else {
            return String(format: String(localized: "profile.explorer.found %lld"), game.foundCount)
        }
        return "\(game.foundInChallenges) / \(expected)"
    }

    private var challengesButton: some View {
        Button(action: onOpenChallenges) {
            HStack {
                Text("profile.discovery.challenges \(state.challengeCount)")
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
