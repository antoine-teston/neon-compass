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
                        header("feed.release.countdown.title")
                        NCCountdownDigits(remaining: remaining)
                    }
                case .released:
                    // Sans libellé à gauche : « Sortie dans / C'est sorti »
                    // se contredirait à voix haute.
                    card {
                        header(nil)
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

    /// La ligne de tête : notre libellé à gauche, le nom du jeu à droite.
    private func header(_ key: LocalizedStringKey?) -> some View {
        HStack(spacing: 8) {
            if let key {
                Text(key)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 8)
            gameName
        }
    }

    /// Le nom du jeu, et rien d'autre.
    ///
    /// **C'est un emplacement nominatif, et sa forme le prouve.** La pastille est
    /// un élément à part dont la valeur ENTIÈRE nomme le produit dont on parle —
    /// le même test que `nominative-fields.mjs` applique au contenu, et la même
    /// distinction que la décision du 8 août 2026 a faite pour le nom App Store :
    /// ce qui compte est la position de la marque, pas sa présence. Notre prose
    /// est à gauche, elle ne contient aucune marque, et les deux ne se mélangent
    /// jamais.
    ///
    /// `verbatim` et non le catalogue : un nom de produit est identique dans les
    /// cinq langues — c'est ce qui en fait un nom et non une phrase. L'app le
    /// fait déjà pour « GTA$ », à cette différence près que celui-là avait été
    /// traduit cinq fois à l'identique. Le garder hors du catalogue a un second
    /// effet, plus utile : la marque ne peut pas être tissée par mégarde dans une
    /// phrase traduite.
    ///
    /// « VI » et non « 6 » : c'est la graphie officielle de l'éditeur, donc
    /// clairement référentielle. Le « 6 » du nom App Store répond à une tout
    /// autre question — ce que les gens tapent dans une barre de recherche — qui
    /// ne se pose pas ici.
    private var gameName: some View {
        Text(verbatim: "GTA VI")
            .breathingHighlight()
            .font(NCTypography.cardMeta)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.08), in: .capsule)
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
