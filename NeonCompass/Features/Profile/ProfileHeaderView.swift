import SwiftUI

/// La carte Identité : qui je suis, où j'en suis.
///
/// Une seule échelle nommée depuis le 2026-08-19 — celle de la rue, calculée
/// sur les lieux cochés, donc locale, donc vivante hors ligne et sans compte.
/// La contribution garde sa ligne de chiffres sous le trait, et n'a plus de
/// dénomination : les deux registres se contredisaient à dix points d'écart.
///
/// La jauge ne double pas les anneaux de la Découverte juste dessous : ceux-ci
/// sont par jeu et en pourcentage d'une collection connue, celle-ci est globale
/// et en nombre absolu. Et le nombre absolu reste juste quand
/// `ChallengeProgress.expected` est nul, ce que le pourcentage ne peut pas.
///
/// Cette vue ne décide de rien : tout est dérivé dans `ProfileHeaderState`,
/// qui est testé. C'est ce qui a fermé le défaut où l'entête se disait anonyme
/// et chiffrée dans le même bloc.
struct ProfileHeaderView: View {
    let state: ProfileHeaderState
    let onContribute: () -> Void

    /// Le conteneur de verre a besoin d'un espace de noms pour fondre la
    /// pastille dans la carte. Sans lui les deux surfaces se superposent sans
    /// se mêler, et l'insigne a l'air collé dessus.
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                titleRow
                rankBlock
                if let contributor = state.contributor {
                    Divider().overlay(Color.white.opacity(0.08))
                    contributorLine(contributor)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
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
                    // La famille chaude dit « ce qui se paie » : le badge, le
                    // paywall et le mot-marque la partagent, et le cyan n'a plus
                    // à signifier deux choses à la fois.
                    .background(NCColor.sunset, in: .capsule)
            }
            // La molette a quitté cet entête pour la barre haute, où elle est
            // atteignable depuis quatre onglets au lieu d'un. Le `Spacer` reste :
            // c'est lui qui garde le titre calé à gauche.
            Spacer()
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch state.title {
        case .handle(let handle):
            styledTitle(Text(handle))
        case .placeholder:
            // Le pseudo arrive : un gabarit plutôt qu'un titre anonyme qui
            // clignoterait le temps de l'aller-retour réseau.
            styledTitle(Text(verbatim: "NEON-XXXXXX-00"))
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        case .neutral:
            styledTitle(Text("profile.header.anonymous"))
        }
    }

    /// Une seule ligne, quoi qu'il arrive.
    ///
    /// `generate_handle()` produit `MOT-MOT-NN` : au pire `ELECTRIC-DRIFTER-29`,
    /// soit 19 caractères — et 24 sur le chemin de repli après dix collisions,
    /// qui ajoute quatre caractères d'UID (`initial_schema.sql:246`). À 28 pt
    /// ça déborde et le titre passait sur deux lignes, ce qui écrasait la jauge
    /// en dessous. 0,6 couvre le pire cas et laisse les pseudos courts en
    /// pleine taille — la réduction n'a lieu que quand elle est nécessaire.
    private func styledTitle(_ text: Text) -> some View {
        text
            .font(NCTypography.displayTitle)
            .foregroundStyle(NCColor.neonCyan)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // MARK: - Insigne et jauge de rang

    private var rankBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                rankBadge
                Spacer()
                foundCountText
            }

            if let progress = state.rankProgress {
                // `Gauge` et non `ProgressView` : ce n'est pas une tâche qui
                // avance, c'est une valeur dans une plage. VoiceOver en tire
                // « 137 sur 250 » au lieu d'un pourcentage nu, et la borne haute
                // du palier devient une donnée du contrôle plutôt qu'un calcul
                // enterré dans l'appelant.
                Gauge(value: progress) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(NCColor.neonCyan)
                .accessibilityHidden(true)
            }

            if let remaining = state.remainingToNext, let nextKey = state.nextRankNameKey {
                Text(remainingLine(remaining: remaining, nextKey: nextKey))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        // Une phrase, pas quatre fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(LocalizedStringKey(state.streetRank.nameKey)))
        .accessibilityValue(Text("profile.explorer.found \(state.foundCount)"))
    }

    /// L'insigne de rang : du verre TEINTÉ, pas un aplat posé derrière du verre.
    ///
    /// Même idiome que `FilterChip` et `CompactTabBar`, et pour la même raison :
    /// empiler un fond opaque sous du verre revient à payer le verre sans le
    /// voir. Le glyphe monte avec le palier et rebondit au changement — c'est le
    /// seul moment où l'app a quelque chose à célébrer.
    private var rankBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: state.streetRank.symbolName)
                .font(.system(size: 12, weight: .bold))
                .symbolEffect(.bounce, value: state.streetRank)
            Text(LocalizedStringKey(state.streetRank.nameKey))
                .font(NCTypography.cardMeta)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(NCColor.neonCyan.opacity(0.45)), in: .capsule)
        .glassEffectID("streetRank", in: glass)
        // Ciblée sur l'insigne : franchir un palier fait changer la teinte, le
        // glyphe et le libellé d'un coup, et sans ça les trois sautent.
        .animation(.snappy(duration: 0.25), value: state.streetRank)
    }

    private var foundCountText: some View {
        Text("profile.explorer.found \(state.foundCount)")
            .font(NCTypography.cardMeta)
            .foregroundStyle(.white.opacity(0.7))
            .monospacedDigit()
            // Cocher un lieu fait rouler le chiffre au lieu de le remplacer
            // sèchement. `monospacedDigit` va avec : sans lui la largeur du
            // texte change pendant la transition et la ligne tremble.
            .contentTransition(.numericText(value: Double(state.foundCount)))
            .animation(.snappy(duration: 0.2), value: state.foundCount)
    }

    /// `NSLocalizedString` et pas `String(localized:)` : la clé du palier
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

        case .ranked(let xp, let rank, let pending):
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.caption2)
                    .foregroundStyle(NCColor.neonCyan)
                Text(rankedSummary(xp: xp, rank: rank, pending: pending))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Composée de fragments déjà traduits plutôt que d'une chaîne de format
    /// par combinaison : le rang et l'attente sont indépendamment absents, ce
    /// qui ferait quatre formats à traduire en cinq langues.
    private func rankedSummary(xp: Int, rank: Int?, pending: Int) -> String {
        var parts: [String] = [String(format: String(localized: "profile.xp.format"), xp)]
        if let rank {
            parts.append(String(format: String(localized: "profile.rank %lld"), rank))
        }
        if pending > 0 {
            parts.append(String(format: String(localized: "profile.pending %lld"), pending))
        }
        return parts.joined(separator: " · ")
    }
}
