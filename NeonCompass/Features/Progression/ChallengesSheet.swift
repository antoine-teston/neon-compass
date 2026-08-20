import SwiftUI

/// Le détail des défis, en feuille.
///
/// C'est `ProgressionListView` moins ses anneaux — la Découverte les porte
/// désormais — et moins sa carte trophées, retirée le 2026-08-19.
///
/// Elle porte son propre `NavigationStack`, et c'est la seule façon d'avoir un
/// titre et un bouton de fermeture ici : aucun écran d'onglet n'a de pile de
/// navigation, donc un `ToolbarItem` posé sur le Profil ne s'afficherait nulle
/// part, sans erreur ni avertissement.
struct ChallengesSheet: View {
    @Bindable var model: ProgressionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(Game.allCases) { game in
                            let challenges = model.challenges(for: game)
                            if !challenges.isEmpty {
                                gameCard(game, challenges)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(Text("challenges.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("challenges.sheet.close") { dismiss() }
                }
            }
        }
    }

    /// Une carte par jeu : les défis d'un volet ne se mélangent pas à ceux d'un
    /// autre. Les jeux sans défi ne sont pas rendus ici — contrairement à la
    /// Découverte, qui les montre exprès : là-bas l'absence est l'information,
    /// ici il n'y aurait rien à lister.
    private func gameCard(_ game: Game, _ challenges: [ChallengeProgress]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: game.shortLabel)
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)
                .breathingHighlight(game == .leonida)

            ForEach(challenges) { challenge in
                challengeRow(challenge)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func challengeRow(_ challenge: ChallengeProgress) -> some View {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(challenge.collection.title.resolved(for: languageCode))
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Spacer()
                Text(tally(for: challenge))
                    .font(NCTypography.body.bold())
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
            if let fraction = challenge.fraction {
                Gauge(value: fraction) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(NCColor.neonCyan)
                    .accessibilityHidden(true)
            }
            // Le joueur qui a tout coché sur nos 47 POI plafonnerait à 47/50
            // sans savoir pourquoi : on dit que le trou est chez nous.
            if challenge.isDataIncomplete {
                Text("progress.challenge.partialData \(challenge.referenced)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// « 12 / 50 » quand le total est connu, « 12 trouvés » sinon.
    private func tally(for challenge: ChallengeProgress) -> String {
        guard let expected = challenge.expected else {
            return String(localized: "progress.challenge.foundCount \(challenge.found)")
        }
        return "\(challenge.found) / \(expected)"
    }
}
