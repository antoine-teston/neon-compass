import SwiftUI

struct ProgressionListView: View {
    @Bindable var model: ProgressionModel

    var body: some View {
        VStack(spacing: 20) {
            ForEach(model.gamesWithChallenges) { game in
                gameCard(game)
            }
            trophyCard
        }
    }

    /// Une carte par jeu : les défis d'un volet ne se mélangent pas à ceux d'un
    /// autre, et chacun a son propre anneau.
    private func gameCard(_ game: MapGame) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text(game.shortLabel)
                    .font(NCTypography.body.bold())
                    .foregroundStyle(NCColor.neonCyan)
                    .breathingHighlight(game == .leonida)
                Spacer()
            }

            // Pas d'anneau tant qu'aucun défi de ce jeu n'a de total connu :
            // afficher 0 % dirait « tu n'as rien trouvé » là où la vérité est
            // « on ne sait pas encore combien il y en a ».
            if let overall = model.overallProgress(for: game) {
                ProgressRing(progress: overall)
                    .frame(width: 140, height: 140)
            }

            VStack(spacing: 14) {
                ForEach(model.challenges(for: game)) { challenge in
                    challengeRow(challenge)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
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
            }
            if let fraction = challenge.fraction {
                ProgressView(value: fraction)
                    .tint(NCColor.neonCyan)
            }
            // Le joueur qui a tout coché sur nos 47 POI plafonnerait à 47/50
            // sans savoir pourquoi : on dit que le trou est chez nous.
            if challenge.isDataIncomplete {
                Text("progress.challenge.partialData \(challenge.referenced)")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    /// « 12 / 50 » quand le total est connu, « 12 trouvés » sinon.
    private func tally(for challenge: ChallengeProgress) -> String {
        guard let expected = challenge.expected else {
            return String(localized: "progress.challenge.foundCount \(challenge.found)")
        }
        return "\(challenge.found) / \(expected)"
    }

    private var trophyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("progress.trophies.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            if model.trophies.isEmpty {
                Text("progress.trophies.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.trophies.enumerated()), id: \.element.id) { index, trophy in
                        trophyRow(trophy)
                        if index < model.trophies.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func trophyRow(_ trophy: Trophy) -> some View {
        Button {
            model.toggleTrophy(trophy)
        } label: {
            HStack {
                Image(systemName: model.isTrophyChecked(trophy) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.isTrophyChecked(trophy) ? NCColor.neonCyan : .white.opacity(0.4))
                Text(trophy.title.resolved(for: currentLanguageCode))
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
