import SwiftUI

/// Entête du Profil : deux jauges, jamais une.
///
/// La haute est LOCALE — elle compte les lieux cochés, elle vit dès le premier
/// POI, hors ligne et sans compte. C'est elle qui porte le mot « niveau » au
/// sens où un joueur l'entend. La basse est SERVEUR, et n'existe que si un
/// profil a pu être lu.
///
/// La jauge haute ne double pas les anneaux de `ProgressionListView` juste
/// dessous : ceux-ci sont par jeu et en pourcentage d'une collection connue,
/// celle-ci est globale et en nombre absolu. Et le nombre absolu reste juste
/// quand `ChallengeProgress.expected` est nul, ce que le pourcentage ne peut
/// pas.
///
/// Cette vue ne décide de rien : tout est dérivé dans `ProfileHeaderState`,
/// qui est testé. C'est ce qui a fermé le défaut où l'entête se disait anonyme
/// et chiffrée dans le même bloc.
struct ProfileHeaderView: View {
    let state: ProfileHeaderState
    let onOpenSettings: () -> Void
    let onContribute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleRow
            explorerGauge
            if let contributor = state.contributor {
                Divider().overlay(Color.white.opacity(0.08))
                contributorLine(contributor)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - Titre

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            titleText
            if state.isProEntitled {
                Text("profile.pro.badge")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(NCColor.nightSky)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NCColor.neonCyan, in: .capsule)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("settings.title"))
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch state.title {
        case .handle(let handle):
            Text(handle)
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)
        case .placeholder:
            // Le pseudo arrive : un gabarit plutôt qu'un titre anonyme qui
            // clignoterait le temps de l'aller-retour réseau.
            Text(verbatim: "NEON-XXXXXX-00")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        case .neutral:
            Text("profile.header.anonymous")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)
        }
    }

    // MARK: - Jauge d'exploration

    private var explorerGauge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(state.explorerGrade.nameKey))
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                Spacer()
                Text("profile.explorer.found \(state.foundCount)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let progress = state.explorerProgress {
                ProgressView(value: progress)
                    .tint(NCColor.neonCyan)
            }

            if let remaining = state.remainingToNext, let nextKey = state.nextGradeNameKey {
                Text(remainingLine(remaining: remaining, nextKey: nextKey))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        // Une phrase, pas quatre fragments.
        .accessibilityElement(children: .combine)
    }

    /// `NSLocalizedString` et pas `String(localized:)` : la clé du grade
    /// suivant est calculée à l'exécution, et `String(localized:)` veut un
    /// littéral. Le catalogue compile toutes ses entrées, référencées
    /// littéralement ou non, donc la résolution est garantie.
    private func remainingLine(remaining: Int, nextKey: String) -> String {
        String(
            format: String(localized: "profile.explorer.remaining %lld %@"),
            remaining,
            NSLocalizedString(nextKey, comment: "")
        )
    }

    // MARK: - Ligne contributeur

    @ViewBuilder
    private func contributorLine(_ contributor: ProfileHeaderState.Contributor) -> some View {
        switch contributor {
        case .invitation:
            Button(action: onContribute) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(NCColor.neonCyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("profile.contribute.invitation")
                            .font(NCTypography.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text("profile.contribute.invitationDetail")
                            .font(NCTypography.cardMeta)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

        case .ranked(let gradeNameKey, let xp, let rank, let pending):
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.caption2)
                    .foregroundStyle(NCColor.neonCyan)
                Text(rankedSummary(gradeNameKey: gradeNameKey, xp: xp, rank: rank, pending: pending))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Composée de fragments déjà traduits plutôt que d'une chaîne de format
    /// par combinaison : le grade, le rang et l'attente sont indépendamment
    /// absents, ce qui ferait huit formats à traduire en cinq langues.
    private func rankedSummary(gradeNameKey: String?, xp: Int, rank: Int?, pending: Int) -> String {
        var parts: [String] = []
        if let gradeNameKey {
            parts.append(NSLocalizedString(gradeNameKey, comment: "").uppercased())
        }
        parts.append(String(format: String(localized: "profile.xp.format"), xp))
        if let rank {
            parts.append(String(format: String(localized: "profile.rank %lld"), rank))
        }
        if pending > 0 {
            parts.append(String(format: String(localized: "profile.pending %lld"), pending))
        }
        return parts.joined(separator: " · ")
    }
}
