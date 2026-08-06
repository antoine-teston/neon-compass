import SwiftUI

/// Le panneau de soumission — placement, envoi, verdict, dans la même surface.
///
/// **Pourquoi un panneau et pas une feuille.** La carte a déjà tranché contre la
/// feuille système pour la fiche d'un POI (voir `MapScreen.detailPanel`) ; ici
/// c'est encore plus net, puisqu'on ajuste une épingle qu'il faut voir. Et
/// surtout : un refus ne referme rien. Sur un 429 il faut attendre, sur un 409
/// déplacer, sur un 400 reformuler — les trois exigent de retrouver ce qu'on
/// avait tapé, qu'une feuille refermée aurait jeté.
struct ContributionPlacementPanel: View {
    @Binding var placement: ContributionPlacement
    let style: MapStyle
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onSeeMine: () -> Void
    let onSignIn: () -> Void

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch placement.phase {
            case .confirmed: confirmation
            default: editor
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }

    // MARK: - Saisie (et refus, qui n'est que la saisie plus un bandeau)

    private var editor: some View {
        Group {
            header
            if let error = placement.error {
                banner(error)
            }
            // Pendant l'envoi, la saisie se fige — changer de catégorie sous une
            // requête déjà partie afficherait une épingle d'une couleur que le
            // serveur n'a jamais reçue. La rangée d'actions, elle, reste vivante :
            // 「Annuler」doit rester atteignable si le réseau traîne.
            ContributionCategoryGrid(selection: $placement.category, style: style)
                .disabled(placement.phase == .sending)
            titleField
                .disabled(placement.phase == .sending)
            actions
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("map.contribution.sheetTitle")
                .font(NCTypography.cardTitle)
                .foregroundStyle(.white)
            // La modération s'annonce AVANT la frappe. L'apprendre au moment où
            // « envoyé » s'affiche arrive trop tard pour changer quoi que ce
            // soit à ce qu'on écrit.
            Text("map.contribution.subtitle")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var titleField: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField("map.contribution.titlePlaceholder", text: $placement.title, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($titleFocused)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                )
            // Le compteur ne s'affiche qu'à l'approche de la borne : permanent,
            // il serait du bruit sur un champ que personne n'approche.
            if placement.showsCounter {
                let over = placement.titleLength > ContributionPlacement.maxTitleLength
                Text(verbatim: "\(placement.titleLength)/\(ContributionPlacement.maxTitleLength)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(over ? NCColor.sunsetMagenta : .white.opacity(0.5))
                    .monospacedDigit()
            }
        }
    }

    /// La rangée d'actions tique à la seconde, pour que le décompte d'un
    /// cooldown descende sous les yeux plutôt que de rester figé jusqu'au
    /// prochain rendu.
    ///
    /// `TimelineView` plutôt qu'un `Timer` en `@State` : il n'y a ni abonnement
    /// à démarrer ni à annuler, donc rien à fuir quand le panneau se referme. Le
    /// coût est de trois vues réévaluées par seconde, sur une surface qui vit
    /// une trentaine de secondes.
    private var actions: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let canSubmit = placement.canSubmit(now: context.date)
            HStack(spacing: 12) {
                Button("map.contribution.cancel", action: onCancel)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if placement.phase == .sending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Button(action: onSubmit) {
                    Text(submitLabel(now: context.date))
                        .monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .tint(NCColor.sunsetMagenta)
                .disabled(!canSubmit)
            }
            .font(NCTypography.cardMeta)
        }
    }

    /// Le bouton PORTE le décompte au lieu de le reléguer au bandeau : c'est lui
    /// qu'on regarde en attendant de pouvoir renvoyer.
    private func submitLabel(now: Date) -> String {
        if let remaining = placement.remainingCooldown(now: now) {
            return String(format: String(localized: "map.contribution.submitIn"), remaining)
        }
        if case .editing(.some) = placement.phase {
            return String(localized: "map.contribution.retry")
        }
        return String(localized: "map.contribution.submit")
    }

    // MARK: - Le bandeau de refus

    @ViewBuilder
    private func banner(_ error: ContributionSubmissionError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(NCColor.sunsetOrange)
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.message(for: error))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                // Un seul remède par refus, et seulement quand il en existe un
                // qui ne soit pas déjà le bouton d'envoi.
                switch error {
                case .duplicateNearby:
                    // Ne déplace rien lui-même : la carte est déjà manipulable
                    // sous le panneau, et bouger l'épingle efface le refus de
                    // lui-même. Le bouton ne fait que dégager le bandeau.
                    Button("map.contribution.error.move") { placement.dismissError() }
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(NCColor.neonCyan)
                case .signedOut:
                    Button("map.contribution.error.signIn", action: onSignIn)
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(NCColor.neonCyan)
                case .titleRejected:
                    Button("map.contribution.error.rename") { titleFocused = true }
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(NCColor.neonCyan)
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(NCColor.sunsetOrange.opacity(0.14))
        )
    }

    /// `static` et `internal` : c'est la table que les tests de couverture de
    /// localisation doivent pouvoir atteindre sans monter une vue.
    static func message(for error: ContributionSubmissionError) -> LocalizedStringKey {
        switch error {
        // Le nombre de secondes vit sur le bouton, pas ici : le bandeau dit
        // POURQUOI, le bouton dit COMBIEN, et le second se rafraîchit.
        case .cooldown: "map.contribution.error.cooldown"
        case .duplicateNearby: "map.contribution.error.duplicate"
        case .titleRejected: "map.contribution.error.vocabulary"
        case .signedOut: "map.contribution.error.signedOut"
        case .disabled: "map.contribution.error.disabled"
        case .failed: "map.contribution.error.failed"
        }
    }

    // MARK: - Confirmation

    private var confirmation: some View {
        Group {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NCColor.neonCyan)
                Text("map.contribution.sent.title")
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
            }
            // Dit où la retrouver, et ce qu'elle rapporte — 20 XP à
            // l'APPROBATION, jamais à l'envoi : `award_contribution_xp` ne
            // crédite rien avant qu'un humain ait tranché.
            Text("map.contribution.sent.message")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("map.contribution.sent.seeMine", action: onSeeMine)
                    .foregroundStyle(NCColor.neonCyan)
                Spacer()
                Button("map.contribution.sent.done", action: onCancel)
                    .buttonStyle(.borderedProminent)
                    .tint(NCColor.sunsetMagenta)
            }
            .font(NCTypography.cardMeta)
        }
    }
}
