import SwiftUI

/// Le panneau du mode parcours, muet : il affiche l'état de la tournée et
/// remonte trois gestes. Marquer trouvé, avancer, sortir — toute la logique
/// vit chez l'appelant, même partage des rôles que `ContributionPlacementPanel`.
///
/// Trois états, une seule surface : tournée vide (tout est déjà trouvé),
/// étape en cours, tournée terminée (l'appelant referme tout seul après ~1 s).
struct RouteModePanel: View {
    let run: RouteRun
    /// Titre du POI courant, résolu par l'appelant : le panneau ne connaît ni
    /// `MapModel` ni la langue. Nil quand la tournée est finie ou vide.
    let currentTitle: String?
    let onValidate: () -> Void
    let onSkip: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if run.totalSteps == 0 {
                empty
            } else if run.isFinished {
                finished
            } else {
                step
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text("map.routePlanner.title")
                .font(NCTypography.cardTitle)
                .foregroundStyle(.white)
            Spacer()
            Button("map.routeMode.exit", systemImage: "xmark.circle.fill", action: onExit)
                .labelStyle(.iconOnly)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var empty: some View {
        Text("map.routePlanner.empty")
            .font(NCTypography.body)
            .foregroundStyle(.white.opacity(0.7))
    }

    private var finished: some View {
        Label("map.routeMode.finished", systemImage: "checkmark.seal.fill")
            .font(NCTypography.body)
            .foregroundStyle(NCColor.neonCyan)
    }

    @ViewBuilder
    private var step: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("map.routeMode.step \(run.stepNumber) \(run.totalSteps)")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
            // Verbatim : le titre arrive déjà résolu dans la langue de
            // l'utilisateur, le catalogue n'a rien à y faire.
            Text(verbatim: currentTitle ?? "")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
        }
        HStack(spacing: 12) {
            Button {
                onValidate()
            } label: {
                Label("map.routeMode.validate", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(NCColor.neonCyan)

            Button("map.routeMode.skip", action: onSkip)
                .buttonStyle(.glass)
        }
    }
}
