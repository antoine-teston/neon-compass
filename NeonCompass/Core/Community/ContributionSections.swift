import Foundation

/// Le découpage du volet Propositions en deux sections. Type pur : ni SwiftUI,
/// ni I/O, ni date « maintenant » — donc entièrement testable.
///
/// **Pourquoi deux sections et pas un tri par score.** Un vote positif rapporte
/// +2 XP à son auteur (`20260802120000_initial_schema.sql:285`). Un classement
/// pur ferait qu'un lieu jamais vu n'est jamais voté, donc reste jamais vu, et
/// son auteur ne décolle pas. « À découvrir » garantit que chaque proposition
/// passe sous les yeux au moins une fois.
struct ContributionSections: Equatable {
    /// Approuvées sur lesquelles je n'ai pas voté, les plus récentes d'abord.
    let discover: [Contribution]

    /// Les meilleures, EXCLUANT ce que `discover` affiche déjà : deux fois la
    /// même ligne dans un écran se lit comme un défaut.
    let top: [Contribution]

    init(spots: [Contribution], myVotes: [String: VoteDirection], limit: Int = 20) {
        // Les dates sont parsées UNE fois, pas à chaque comparaison : un
        // comparateur qui construirait un `ISO8601DateFormatter` par appel en
        // ferait des milliers pour un seul tri.
        //
        // `uniquingKeysWith` et non `uniqueKeysWithValues` : ce dernier plante
        // sur un doublon d'identifiant. La base l'interdit, mais un fragment
        // corrompu ne doit pas faire tomber l'écran.
        let dates = Dictionary(
            spots.map { ($0.id, $0.approvedAtDate) },
            uniquingKeysWith: { first, _ in first }
        )

        discover = Array(
            spots
                .filter { myVotes[$0.id] == nil }
                .sorted { left, right in
                    switch (dates[left.id] ?? nil, dates[right.id] ?? nil) {
                    // Une ligne sans date vient d'un fragment mis en cache avant
                    // l'ajout de la colonne : elle passe en fin plutôt que de
                    // disparaître ou de remonter en tête.
                    case (nil, nil): return left.id < right.id
                    case (nil, _): return false
                    case (_, nil): return true
                    case (let leftDate?, let rightDate?):
                        return leftDate == rightDate ? left.id < right.id : leftDate > rightDate
                    }
                }
                .prefix(limit)
        )

        let shown = Set(discover.map(\.id))
        top = Array(
            spots
                .filter { !shown.contains($0.id) }
                // Départage par identifiant, et ce n'est pas cosmétique : au
                // démarrage tous les scores valent zéro, et un tri instable
                // ferait sauter les lignes à chaque réévaluation de la vue.
                .sorted { left, right in
                    let leftScore = left.upvotes - left.downvotes
                    let rightScore = right.upvotes - right.downvotes
                    return leftScore == rightScore ? left.id < right.id : leftScore > rightScore
                }
                .prefix(limit)
        )
    }
}
