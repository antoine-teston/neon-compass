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
    /// Les instructions du lieu (`POI.note`), déjà résolues dans la langue de
    /// l'utilisateur par l'appelant. Nil quand le lieu n'en a pas — 11 des 152
    /// collectibles sont dans ce cas, et le panneau doit alors n'afficher
    /// AUCUNE place vide.
    let currentNote: String?
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
            if let currentNote, !currentNote.isEmpty {
                // Même traitement que la fiche : `ViewThatFits` prend la hauteur
                // naturelle de la note si elle tient dans ce qu'on lui propose, et
                // bascule sur une version défilante sinon. Le panneau suit donc son
                // texte au lieu de se figer, et une note de 440 caractères n'avale
                // pas la carte. Le plafond n'est PAS posé ici : c'est l'appelant qui
                // borne ce qu'il PROPOSE (voir `MapScreen`), parce qu'un
                // `.frame(maxHeight:)` posé ici prendrait toute la hauteur proposée
                // et centrerait une note de deux lignes au milieu du vide.
                ViewThatFits(in: .vertical) {
                    noteText(currentNote)
                    ScrollView { noteText(currentNote) }
                        .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.top, 4)
            }
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

    private func noteText(_ note: String) -> some View {
        // Verbatim, comme le titre : la note arrive déjà résolue dans la langue
        // de l'utilisateur, le catalogue n'a rien à y faire.
        Text(verbatim: note)
            .font(NCTypography.body)
            .foregroundStyle(.white.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
