import SwiftUI

/// Le compte à rebours jusqu'à la sortie du jeu, en tête du fil.
///
/// En tête du fil et non dans la barre haute : c'est l'information la plus
/// attendue de toute l'app, elle mérite des chiffres qu'on lit de loin plutôt
/// qu'une mention tassée à côté du logo. Le prix est qu'elle disparaît au
/// premier geste de défilement, ce qui est le bon prix — on ne consulte pas un
/// rebours en continu, on vient le voir.
///
/// Le libellé ne nomme pas le jeu, et c'est une contrainte, pas un oubli : la
/// marque reste interdite dans la prose que nous écrivons (`CLAUDE.md`). Sur
/// l'onglet Actu d'une app compagnon, « Sortie dans » ne désigne de toute façon
/// rien d'autre.
struct ReleaseCountdownCard: View {
    /// Injectable pour que les tests et les aperçus puissent se placer de part
    /// et d'autre du jour J sans toucher à l'horloge de la machine.
    var calendar: Calendar = .current

    var body: some View {
        // Évalué une fois au montage, avant toute minuterie : passé la fenêtre,
        // aucun `TimelineView` n'est créé, donc rien ne bat à la seconde pour ne
        // rien afficher. Une app ne reste pas ouverte les sept jours qu'il
        // faudrait pour que cette lecture se périme en cours de route.
        if case .gone = GameRelease.phase(at: .now, calendar: calendar) {
            EmptyView()
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                switch GameRelease.phase(at: context.date, calendar: calendar) {
                case .countdown(let remaining):
                    card {
                        title("feed.release.countdown.title")
                        NCCountdownDigits(remaining: remaining)
                    }
                case .released:
                    // Sans libellé au-dessus : « Sortie dans / C'est sorti »
                    // se contredirait à voix haute.
                    card {
                        Text("feed.release.out")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(NCColor.sunsetMagenta)
                            .ncNeonGlow(NCColor.sunsetMagenta)
                    }
                case .gone:
                    EmptyView()
                }
            }
        }
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(NCTypography.cardMeta)
            .foregroundStyle(.white.opacity(0.5))
    }

    /// Même gabarit qu'une carte du fil — mêmes marges, même rayon, même verre.
    /// Un encart d'une autre taille en tête d'une colonne de cartes casse le
    /// rythme de lecture avant même qu'on ait lu ce qu'il contient.
    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
